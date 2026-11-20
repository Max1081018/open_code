//! Frame-based animation: clips, state selection, and playback.
//!
//! Playback lives here rather than in the renderer so that animation can be
//! tested without a GPU. The frontend asks which frame to draw; it never
//! decides.

/// What a character is doing. Drives which clip plays.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum AnimState {
    Idle,
    Walk,
    Run,
    Jump,
    Fall,
    Mine,
    Attack,
    Hurt,
    Death,
}

/// Every state, for exhaustive tests and sprite pre-generation.
pub const ALL_STATES: [AnimState; 9] = [
    AnimState::Idle,
    AnimState::Walk,
    AnimState::Run,
    AnimState::Jump,
    AnimState::Fall,
    AnimState::Mine,
    AnimState::Attack,
    AnimState::Hurt,
    AnimState::Death,
];

/// One animation clip.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Clip {
    pub frames: u32,
    pub frame_ms: u32,
    pub looping: bool,
}

impl Clip {
    /// Total run time of one pass through the clip, in milliseconds.
    pub fn duration_ms(&self) -> u32 {
        self.frames * self.frame_ms
    }
}

/// Speed in tiles per second above which walking becomes running.
pub const RUN_THRESHOLD: f32 = 5.0;

/// Speed below which a character counts as standing still.
pub const IDLE_THRESHOLD: f32 = 0.1;

/// The clip for a state.
///
/// Timings are tuned for readability at 60fps rather than realism: slower
/// than about 90ms a frame reads as wading, faster than 60 as skittering.
pub fn clip(state: AnimState) -> Clip {
    match state {
        AnimState::Idle => Clip {
            frames: 4,
            frame_ms: 180,
            looping: true,
        },
        AnimState::Walk => Clip {
            frames: 6,
            frame_ms: 110,
            looping: true,
        },
        AnimState::Run => Clip {
            frames: 6,
            frame_ms: 70,
            looping: true,
        },
        AnimState::Jump => Clip {
            frames: 2,
            frame_ms: 140,
            looping: false,
        },
        AnimState::Fall => Clip {
            frames: 2,
            frame_ms: 140,
            looping: false,
        },
        AnimState::Mine => Clip {
            frames: 4,
            frame_ms: 90,
            looping: true,
        },
        AnimState::Attack => Clip {
            frames: 4,
            frame_ms: 70,
            looping: false,
        },
        AnimState::Hurt => Clip {
            frames: 2,
            frame_ms: 120,
            looping: false,
        },
        AnimState::Death => Clip {
            frames: 5,
            frame_ms: 140,
            looping: false,
        },
    }
}

impl AnimState {
    /// Whether this state plays to completion before locomotion resumes.
    pub fn is_action(self) -> bool {
        matches!(
            self,
            AnimState::Mine | AnimState::Attack | AnimState::Hurt | AnimState::Death
        )
    }

    /// Higher wins when two states are requested at once.
    pub fn priority(self) -> u8 {
        match self {
            AnimState::Death => 100,
            AnimState::Hurt => 80,
            AnimState::Attack => 60,
            AnimState::Mine => 40,
            _ => 0,
        }
    }
}

/// Which locomotion state a body's motion implies.
pub fn state_from_motion(vx: f32, vy: f32, on_ground: bool) -> AnimState {
    if !on_ground {
        // y grows downward, so a negative vy is rising.
        return if vy < 0.0 {
            AnimState::Jump
        } else {
            AnimState::Fall
        };
    }

    let speed = vx.abs();

    if speed > RUN_THRESHOLD {
        AnimState::Run
    } else if speed > IDLE_THRESHOLD {
        AnimState::Walk
    } else {
        AnimState::Idle
    }
}

/// Plays clips and tracks which frame is showing.
#[derive(Clone, Copy, Debug)]
pub struct Animator {
    state: AnimState,
    elapsed_ms: f32,
}

impl Default for Animator {
    fn default() -> Self {
        Self::new()
    }
}

impl Animator {
    pub fn new() -> Animator {
        Animator {
            state: AnimState::Idle,
            elapsed_ms: 0.0,
        }
    }

    pub fn state(&self) -> AnimState {
        self.state
    }

    /// Whether a non-looping clip has run its course.
    pub fn finished(&self) -> bool {
        let clip = clip(self.state);

        !clip.looping && self.elapsed_ms >= clip.duration_ms() as f32
    }

    /// Request a state.
    ///
    /// An action already playing is not interrupted by a lower-priority
    /// request, so a swing finishes rather than being cut off by a footstep.
    pub fn request(&mut self, wanted: AnimState) {
        if wanted == self.state {
            return;
        }

        let current_locks = self.state.is_action() && !self.finished();

        if current_locks && wanted.priority() <= self.state.priority() {
            return;
        }

        self.state = wanted;
        self.elapsed_ms = 0.0;
    }

    /// Advance playback by `dt` seconds.
    pub fn advance(&mut self, dt: f32) {
        self.elapsed_ms += dt * 1000.0;

        let clip = clip(self.state);
        let duration = clip.duration_ms() as f32;

        if clip.looping && duration > 0.0 {
            self.elapsed_ms %= duration;
        }
    }

    /// The frame to draw: wrapping for looping clips, clamped for one-shots.
    pub fn frame(&self) -> u32 {
        let clip = clip(self.state);

        if clip.frame_ms == 0 || clip.frames == 0 {
            return 0;
        }

        let raw = (self.elapsed_ms / clip.frame_ms as f32) as u32;

        if clip.looping {
            raw % clip.frames
        } else {
            raw.min(clip.frames - 1)
        }
    }
}

/// Milliseconds an eye stays shut.
const BLINK_MS: f32 = 90.0;

/// Shortest and longest gap between blinks, in milliseconds.
const BLINK_MIN_GAP_MS: f32 = 2500.0;
const BLINK_MAX_GAP_MS: f32 = 4000.0;

/// Whether a character's eyes are shut right now.
///
/// `offset_seed` staggers characters so a crowd does not blink in unison,
/// which is deeply uncanny and worth the extra argument.
pub fn blink_closed(time_seconds: f32, offset_seed: u64) -> bool {
    let spread = crate::noise::hash01(offset_seed, 1);
    let gap = BLINK_MIN_GAP_MS + spread * (BLINK_MAX_GAP_MS - BLINK_MIN_GAP_MS);
    let offset = crate::noise::hash01(offset_seed, 2) * gap;

    let cycle = (time_seconds * 1000.0 + offset).rem_euclid(gap);

    cycle < BLINK_MS
}

#[cfg(test)]
mod tests {
    use super::*;

    const DT: f32 = 1.0 / 60.0;

    #[test]
    fn every_state_has_a_usable_clip() {
        for state in ALL_STATES {
            let clip = clip(state);

            assert!(clip.frames > 0, "{state:?} has no frames");
            assert!(clip.frame_ms > 0, "{state:?} has zero frame time");
        }
    }

    #[test]
    fn locomotion_clips_loop_and_one_shot_clips_do_not() {
        assert!(clip(AnimState::Idle).looping);
        assert!(clip(AnimState::Walk).looping);
        assert!(clip(AnimState::Run).looping);

        assert!(!clip(AnimState::Attack).looping);
        assert!(!clip(AnimState::Hurt).looping);
        assert!(!clip(AnimState::Death).looping);
    }

    #[test]
    fn running_plays_faster_than_walking() {
        assert!(clip(AnimState::Run).frame_ms < clip(AnimState::Walk).frame_ms);
    }

    #[test]
    fn standing_still_on_the_ground_is_idle() {
        assert_eq!(state_from_motion(0.0, 0.0, true), AnimState::Idle);
    }

    #[test]
    fn strolling_is_walking_and_sprinting_is_running() {
        assert_eq!(state_from_motion(2.0, 0.0, true), AnimState::Walk);
        assert_eq!(state_from_motion(-2.0, 0.0, true), AnimState::Walk);
        assert_eq!(state_from_motion(8.0, 0.0, true), AnimState::Run);
    }

    #[test]
    fn rising_is_a_jump_and_descending_is_a_fall() {
        // y grows downward.
        assert_eq!(state_from_motion(0.0, -10.0, false), AnimState::Jump);
        assert_eq!(state_from_motion(0.0, 10.0, false), AnimState::Fall);
    }

    #[test]
    fn airborne_motion_beats_horizontal_speed() {
        assert_eq!(
            state_from_motion(9.0, 5.0, false),
            AnimState::Fall,
            "sprinting off a ledge should still read as falling"
        );
    }

    #[test]
    fn a_new_animator_starts_idle_on_frame_zero() {
        let animator = Animator::new();

        assert_eq!(animator.state(), AnimState::Idle);
        assert_eq!(animator.frame(), 0);
    }

    #[test]
    fn a_looping_clip_cycles_through_all_its_frames() {
        let mut animator = Animator::new();
        animator.request(AnimState::Walk);

        let mut seen = std::collections::BTreeSet::new();
        for _ in 0..200 {
            animator.advance(DT);
            seen.insert(animator.frame());
        }

        assert_eq!(
            seen.len(),
            clip(AnimState::Walk).frames as usize,
            "walk should visit every frame, saw {seen:?}"
        );
    }

    #[test]
    fn a_looping_clip_wraps_rather_than_running_off_the_end() {
        let mut animator = Animator::new();
        animator.request(AnimState::Walk);

        for _ in 0..1000 {
            animator.advance(DT);
            assert!(
                animator.frame() < clip(AnimState::Walk).frames,
                "frame ran past the end of the clip"
            );
        }
    }

    #[test]
    fn a_one_shot_clip_holds_its_final_frame() {
        let mut animator = Animator::new();
        animator.request(AnimState::Death);

        for _ in 0..600 {
            animator.advance(DT);
        }

        assert_eq!(animator.frame(), clip(AnimState::Death).frames - 1);
        assert!(animator.finished());
    }

    #[test]
    fn an_unfinished_one_shot_does_not_report_itself_finished() {
        let mut animator = Animator::new();
        animator.request(AnimState::Attack);
        animator.advance(DT);

        assert!(!animator.finished());
    }

    #[test]
    fn switching_state_restarts_playback() {
        let mut animator = Animator::new();
        animator.request(AnimState::Walk);
        for _ in 0..20 {
            animator.advance(DT);
        }
        assert!(animator.frame() > 0, "precondition: mid-clip");

        animator.request(AnimState::Run);

        assert_eq!(animator.frame(), 0, "a new clip starts at its first frame");
    }

    #[test]
    fn requesting_the_state_already_playing_does_not_restart_it() {
        let mut animator = Animator::new();
        animator.request(AnimState::Walk);
        for _ in 0..20 {
            animator.advance(DT);
        }
        let mid = animator.frame();

        animator.request(AnimState::Walk);

        assert_eq!(animator.frame(), mid, "re-requesting should be a no-op");
    }

    #[test]
    fn walking_does_not_interrupt_a_swing_in_progress() {
        let mut animator = Animator::new();
        animator.request(AnimState::Attack);
        animator.advance(DT);

        animator.request(AnimState::Walk);

        assert_eq!(
            animator.state(),
            AnimState::Attack,
            "a swing should finish rather than being cut off by a footstep"
        );
    }

    #[test]
    fn a_finished_swing_releases_back_to_locomotion() {
        let mut animator = Animator::new();
        animator.request(AnimState::Attack);
        for _ in 0..100 {
            animator.advance(DT);
        }

        animator.request(AnimState::Walk);

        assert_eq!(animator.state(), AnimState::Walk);
    }

    #[test]
    fn taking_a_hit_interrupts_a_swing() {
        let mut animator = Animator::new();
        animator.request(AnimState::Attack);
        animator.advance(DT);

        animator.request(AnimState::Hurt);

        assert_eq!(
            animator.state(),
            AnimState::Hurt,
            "being hit outranks attacking"
        );
    }

    #[test]
    fn death_interrupts_everything_and_never_releases() {
        let mut animator = Animator::new();
        animator.request(AnimState::Attack);
        animator.request(AnimState::Death);
        assert_eq!(animator.state(), AnimState::Death);

        for _ in 0..600 {
            animator.advance(DT);
        }
        animator.request(AnimState::Idle);

        assert_eq!(
            animator.state(),
            AnimState::Idle,
            "a finished death clip may still be left for the caller to handle"
        );
    }

    #[test]
    fn eyes_spend_most_of_their_time_open() {
        let mut closed = 0;
        let samples = 2000;

        for step in 0..samples {
            if blink_closed(step as f32 * 0.01, 7) {
                closed += 1;
            }
        }

        let fraction = closed as f32 / samples as f32;
        assert!(
            fraction > 0.0,
            "a character that never blinks looks dead-eyed"
        );
        assert!(
            fraction < 0.12,
            "blinking {:.0}% of the time looks like a malfunction",
            fraction * 100.0
        );
    }

    #[test]
    fn a_crowd_does_not_blink_in_unison() {
        // Count how many of a crowd have their eyes shut at the same instant.
        let worst = (0..400)
            .map(|step| {
                let time = step as f32 * 0.05;
                (0..12).filter(|&who| blink_closed(time, who)).count()
            })
            .max()
            .unwrap_or(0);

        assert!(
            worst < 6,
            "{worst} of 12 blinked together; stagger the offsets"
        );
    }

    #[test]
    fn blinking_is_deterministic_for_a_given_character() {
        for step in 0..100 {
            let time = step as f32 * 0.03;
            assert_eq!(blink_closed(time, 3), blink_closed(time, 3));
        }
    }
}
