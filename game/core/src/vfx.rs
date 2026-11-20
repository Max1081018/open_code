//! Particles, screen shake and floating text.
//!
//! The particle store is a fixed-capacity pool. It never grows and never
//! allocates while the game runs, because an effects system that allocates
//! under load is exactly the thing that stutters on a phone.

use crate::noise::hash01;

/// What a particle is, which decides how it moves and fades.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ParticleKind {
    /// Chips of the tile being broken. Heavy, bounces off nothing, fades fast.
    Debris,
    /// Bright flecks from a weapon landing. Fast, short-lived.
    Spark,
    /// Kicked up by footfalls and landings. Drifts and spreads.
    Dust,
    /// Rises rather than falls, for torches and lava.
    Ember,
}

impl ParticleKind {
    /// Multiplier on gravity. Embers rise.
    pub fn gravity_scale(self) -> f32 {
        match self {
            ParticleKind::Debris => 1.0,
            ParticleKind::Spark => 0.55,
            ParticleKind::Dust => 0.10,
            ParticleKind::Ember => -0.35,
        }
    }

    /// Fraction of speed kept each second, as air resistance.
    pub fn drag(self) -> f32 {
        match self {
            ParticleKind::Debris => 0.92,
            ParticleKind::Spark => 0.80,
            ParticleKind::Dust => 0.55,
            ParticleKind::Ember => 0.70,
        }
    }
}

/// One live particle. Positions are in tiles, matching the rest of the game.
#[derive(Clone, Copy, Debug)]
pub struct Particle {
    pub x: f32,
    pub y: f32,
    pub vx: f32,
    pub vy: f32,
    /// Seconds remaining.
    pub life: f32,
    /// Seconds this particle started with, for computing fade.
    pub max_life: f32,
    pub kind: ParticleKind,
    pub colour: [f32; 3],
    /// Edge length in tiles.
    pub size: f32,
}

impl Particle {
    /// How far through its life this particle is, from 0.0 to 1.0.
    pub fn age(&self) -> f32 {
        if self.max_life <= 0.0 {
            return 1.0;
        }
        (1.0 - self.life / self.max_life).clamp(0.0, 1.0)
    }

    /// Opacity, fading out over the back half of the particle's life.
    pub fn alpha(&self) -> f32 {
        (1.0 - self.age()).min(1.0).powf(0.6)
    }
}

/// Downward acceleration applied to particles, in tiles per second squared.
pub const PARTICLE_GRAVITY: f32 = 26.0;

/// A fixed-capacity particle pool.
pub struct Particles {
    live: Vec<Particle>,
    capacity: usize,
    /// Advances on every burst so repeated bursts differ.
    ticket: u64,
}

impl Particles {
    pub fn new(capacity: usize) -> Particles {
        Particles {
            live: Vec::with_capacity(capacity),
            capacity,
            ticket: 0,
        }
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn count(&self) -> usize {
        self.live.len()
    }

    pub fn live(&self) -> &[Particle] {
        &self.live
    }

    pub fn clear(&mut self) {
        self.live.clear();
    }

    /// Add one particle, discarding the oldest if the pool is full.
    pub fn spawn(&mut self, particle: Particle) {
        if self.capacity == 0 {
            return;
        }

        if self.live.len() >= self.capacity {
            // Drop the oldest rather than refusing the newest: the effect
            // the player just caused matters more than one already fading.
            self.live.remove(0);
        }

        self.live.push(particle);
    }

    /// Chips flying off a tile being broken.
    pub fn burst_mining(&mut self, x: f32, y: f32, colour: [f32; 3]) {
        self.ticket += 1;
        let ticket = self.ticket;

        for index in 0..10 {
            let roll = |salt: i64| hash01(ticket, index * 8 + salt);

            self.spawn(Particle {
                x: x + roll(1) - 0.5,
                y: y + roll(2) - 0.5,
                vx: (roll(3) - 0.5) * 7.0,
                vy: -roll(4) * 6.0,
                life: 0.35 + roll(5) * 0.45,
                max_life: 0.8,
                kind: ParticleKind::Debris,
                // Slight per-chip variation so debris is not one flat colour.
                colour: [
                    (colour[0] * (0.8 + roll(6) * 0.4)).min(255.0),
                    (colour[1] * (0.8 + roll(6) * 0.4)).min(255.0),
                    (colour[2] * (0.8 + roll(6) * 0.4)).min(255.0),
                ],
                size: 0.08 + roll(7) * 0.10,
            });
        }
    }

    /// Bright flecks where a blow lands.
    pub fn burst_hit(&mut self, x: f32, y: f32) {
        self.ticket += 1;
        let ticket = self.ticket;

        for index in 0..8 {
            let roll = |salt: i64| hash01(ticket, index * 8 + salt);
            let angle = roll(1) * std::f32::consts::TAU;
            let speed = 4.0 + roll(2) * 7.0;

            self.spawn(Particle {
                x,
                y,
                vx: angle.cos() * speed,
                vy: angle.sin() * speed,
                life: 0.16 + roll(3) * 0.20,
                max_life: 0.36,
                kind: ParticleKind::Spark,
                colour: [255.0, 214.0 - roll(4) * 70.0, 120.0],
                size: 0.06 + roll(5) * 0.07,
            });
        }
    }

    /// A low puff, for footfalls and landings.
    pub fn burst_dust(&mut self, x: f32, y: f32, colour: [f32; 3]) {
        self.ticket += 1;
        let ticket = self.ticket;

        for index in 0..6 {
            let roll = |salt: i64| hash01(ticket, index * 8 + salt);

            self.spawn(Particle {
                x: x + (roll(1) - 0.5) * 0.8,
                y,
                vx: (roll(2) - 0.5) * 3.2,
                vy: -roll(3) * 1.6,
                life: 0.25 + roll(4) * 0.35,
                max_life: 0.6,
                kind: ParticleKind::Dust,
                colour,
                size: 0.12 + roll(5) * 0.14,
            });
        }
    }

    /// Advance every particle and retire the expired ones.
    pub fn step(&mut self, dt: f32) {
        for particle in self.live.iter_mut() {
            particle.vy += PARTICLE_GRAVITY * particle.kind.gravity_scale() * dt;

            let keep = particle.kind.drag().powf(dt);
            particle.vx *= keep;
            particle.vy *= keep;

            particle.x += particle.vx * dt;
            particle.y += particle.vy * dt;
            particle.life -= dt;
        }

        self.live.retain(|particle| particle.life > 0.0);
    }
}

/// Camera shake, as a decaying intensity.
#[derive(Clone, Copy, Debug, Default)]
pub struct ScreenShake {
    intensity: f32,
}

/// How fast shake dies away, as a fraction kept per second.
const SHAKE_DECAY: f32 = 0.04;

/// Hard cap, so a flurry of hits cannot make the screen unreadable.
pub const MAX_SHAKE: f32 = 1.0;

/// Below this the shake is rounded away, in tiles.
const SHAKE_REST: f32 = 0.005;

impl ScreenShake {
    pub fn new() -> ScreenShake {
        ScreenShake::default()
    }

    pub fn intensity(&self) -> f32 {
        self.intensity
    }

    /// Add a jolt.
    pub fn add(&mut self, amount: f32) {
        self.intensity = (self.intensity + amount).clamp(0.0, MAX_SHAKE);
    }

    pub fn step(&mut self, dt: f32) {
        self.intensity *= SHAKE_DECAY.powf(dt);

        // Snap to rest rather than drifting imperceptibly for ever. At the
        // game's scale this threshold is well under half a pixel.
        if self.intensity < SHAKE_REST {
            self.intensity = 0.0;
        }
    }

    /// Camera displacement in tiles at `time`.
    pub fn offset(&self, time: f32) -> (f32, f32) {
        if self.intensity <= 0.0 {
            return (0.0, 0.0);
        }

        // Two incommensurable frequencies, so the motion does not look like
        // a regular oscillation.
        let x = (time * 61.0).sin() * self.intensity * 0.45;
        let y = (time * 47.0).cos() * self.intensity * 0.45;

        (x, y)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DT: f32 = 1.0 / 60.0;
    const ROCK: [f32; 3] = [118.0, 118.0, 126.0];

    #[test]
    fn a_new_pool_is_empty() {
        let particles = Particles::new(64);

        assert_eq!(particles.count(), 0);
        assert!(particles.live().is_empty());
    }

    #[test]
    fn mining_throws_off_a_handful_of_chips() {
        let mut particles = Particles::new(256);

        particles.burst_mining(10.0, 20.0, ROCK);

        assert!(
            particles.count() >= 6,
            "a pick strike should throw more than {} chips",
            particles.count()
        );
    }

    #[test]
    fn chips_start_near_the_tile_that_was_broken() {
        let mut particles = Particles::new(256);

        particles.burst_mining(10.0, 20.0, ROCK);

        for particle in particles.live() {
            assert!(
                (particle.x - 10.0).abs() < 1.5 && (particle.y - 20.0).abs() < 1.5,
                "chip at ({}, {}) is nowhere near the tile",
                particle.x,
                particle.y
            );
        }
    }

    #[test]
    fn chips_take_their_colour_from_the_tile() {
        let mut particles = Particles::new(256);

        particles.burst_mining(10.0, 20.0, ROCK);

        for particle in particles.live() {
            // Within the per-chip variation band of the source colour.
            assert!(
                (particle.colour[0] - ROCK[0]).abs() < ROCK[0] * 0.5,
                "chip colour {:?} does not resemble the rock it came from",
                particle.colour
            );
        }
    }

    #[test]
    fn the_pool_never_grows_past_its_capacity() {
        let mut particles = Particles::new(20);

        for _ in 0..50 {
            particles.burst_mining(5.0, 5.0, ROCK);
        }

        assert_eq!(
            particles.count(),
            20,
            "the pool must stay bounded no matter how much happens at once"
        );
    }

    #[test]
    fn a_zero_capacity_pool_quietly_accepts_nothing() {
        let mut particles = Particles::new(0);

        particles.burst_hit(1.0, 1.0);

        assert_eq!(particles.count(), 0);
    }

    #[test]
    fn particles_move_along_their_velocity() {
        let mut particles = Particles::new(8);
        particles.spawn(Particle {
            x: 0.0,
            y: 0.0,
            vx: 10.0,
            vy: 0.0,
            life: 5.0,
            max_life: 5.0,
            kind: ParticleKind::Dust,
            colour: ROCK,
            size: 0.1,
        });

        particles.step(0.1);

        assert!(
            particles.live()[0].x > 0.3,
            "a particle with speed should have moved"
        );
    }

    #[test]
    fn debris_falls_but_embers_rise() {
        let make = |kind| Particle {
            x: 0.0,
            y: 0.0,
            vx: 0.0,
            vy: 0.0,
            life: 5.0,
            max_life: 5.0,
            kind,
            colour: ROCK,
            size: 0.1,
        };

        let mut particles = Particles::new(8);
        particles.spawn(make(ParticleKind::Debris));
        particles.spawn(make(ParticleKind::Ember));

        for _ in 0..20 {
            particles.step(DT);
        }

        // y grows downward.
        assert!(particles.live()[0].y > 0.0, "debris should fall");
        assert!(particles.live()[1].y < 0.0, "embers should rise");
    }

    #[test]
    fn particles_expire_and_are_retired() {
        let mut particles = Particles::new(64);
        particles.burst_hit(0.0, 0.0);
        assert!(particles.count() > 0, "precondition: sparks exist");

        for _ in 0..200 {
            particles.step(DT);
        }

        assert_eq!(particles.count(), 0, "sparks should not live for ever");
    }

    #[test]
    fn a_fresh_particle_is_opaque_and_an_old_one_is_not() {
        let mut particles = Particles::new(8);
        particles.burst_hit(0.0, 0.0);

        let fresh = particles.live()[0].alpha();

        for _ in 0..12 {
            particles.step(DT);
        }
        let older = particles.live().first().map(|p| p.alpha()).unwrap_or(0.0);

        assert!(fresh > older, "particles should fade as they age");
    }

    #[test]
    fn bursts_differ_from_one_another() {
        let mut particles = Particles::new(256);

        particles.burst_hit(0.0, 0.0);
        let first: Vec<f32> = particles.live().iter().map(|p| p.vx).collect();

        particles.clear();
        particles.burst_hit(0.0, 0.0);
        let second: Vec<f32> = particles.live().iter().map(|p| p.vx).collect();

        assert_ne!(first, second, "every burst should not look identical");
    }

    #[test]
    fn sparks_fly_outward_in_all_directions() {
        let mut particles = Particles::new(64);
        particles.burst_hit(0.0, 0.0);

        let right = particles.live().iter().filter(|p| p.vx > 0.0).count();
        let left = particles.live().iter().filter(|p| p.vx < 0.0).count();

        assert!(right > 0 && left > 0, "an impact should scatter both ways");
    }

    #[test]
    fn a_still_camera_does_not_shake() {
        let shake = ScreenShake::new();

        assert_eq!(shake.offset(1.0), (0.0, 0.0));
    }

    #[test]
    fn a_jolt_moves_the_camera() {
        let mut shake = ScreenShake::new();
        shake.add(0.5);

        let (x, y) = shake.offset(0.3);

        assert!(x.abs() + y.abs() > 0.0, "a jolt should displace the camera");
    }

    #[test]
    fn shake_dies_away() {
        let mut shake = ScreenShake::new();
        shake.add(1.0);

        for _ in 0..120 {
            shake.step(DT);
        }

        assert_eq!(
            shake.intensity(),
            0.0,
            "shake should settle rather than ringing for ever"
        );
    }

    #[test]
    fn shake_is_capped_however_much_happens_at_once() {
        let mut shake = ScreenShake::new();

        for _ in 0..100 {
            shake.add(0.9);
        }

        assert!(
            shake.intensity() <= MAX_SHAKE,
            "a flurry of hits must not make the screen unreadable"
        );
    }

    #[test]
    fn shake_displacement_stays_within_its_intensity() {
        let mut shake = ScreenShake::new();
        shake.add(MAX_SHAKE);

        for step in 0..500 {
            let (x, y) = shake.offset(step as f32 * 0.01);

            assert!(x.abs() <= MAX_SHAKE && y.abs() <= MAX_SHAKE);
        }
    }
}
