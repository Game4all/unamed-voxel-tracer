const znoise = @import("znoise");
const std = @import("std");

pub const LCG = struct {
    seed: u32,

    pub fn rand(self: *@This()) u32 {
        self.seed = @addWithOverflow(@mulWithOverflow(self.seed, 1103515245).@"0", 12345).@"0";

        return self.seed;
    }
};

pub fn procgen(comptime dim: comptime_int, world: anytype, offsetX: f32, offsetY: f32) void {
    const height_gen = znoise.FnlGenerator{ .fractal_type = .fbm };
    var lcg = LCG{ .seed = 0x46AE4F };

    for (0..dim) |x| {
        for (0..dim) |z| {
            for (0..16) |y| {
                world.set(x, y, z, 0x00E6D8AD); // ADD8E6
            }
        }
    }

    for (0..dim) |x| {
        for (0..dim) |z| {
            const val = height_gen.noise2((offsetX + @as(f32, @floatFromInt(x))) / 10.0, (offsetY + @as(f32, @floatFromInt(z))) / 10.0);
            const vh: u32 = @intFromFloat(@max(val * @as(f32, @floatFromInt(dim)) * 0.1, 0.0));

            for (0..vh) |h| {
                world.set(x, h, z, 0x0000fc7c); // grass 7CFC00
            }

            if (vh > 15) {
                // add future grass blades
                if (lcg.rand() % 5 == 0)
                    world.set(x, vh, z, 0x01000000 + lcg.rand() % 4); //dirt

                if (lcg.rand() % 71 == 0)
                    world.set(x, vh, z, 0x01000000 + 4); //dirt

                // stones
                if (lcg.rand() % 2120 == 0) {
                    world.set(x, vh, z, 0x01000000 + 5); //dirt
                    continue;
                }

                if (lcg.rand() % 420 == 0 and x < 510 and z < 510 and x > 2 and z > 2) {
                    for (0..8) |offset| {
                        world.set(x, vh + offset, z, 0x425E85); // 855E42
                    }

                    // inline for (-2..2, 0..3, -2..2) |ox, oy, oz| {
                    //     world.set(x + ox, vh + 7 + oy, z + oz, 0xFFFFFF);
                    // }

                    world.set(x, vh + 8, z, 0xFFFFFF);
                    world.set(x + 1, vh + 7, z, 0xFFFFFF);
                    world.set(x - 1, vh + 7, z, 0xFFFFFF);
                    world.set(x, vh + 7, z + 1, 0xFFFFFF);
                    world.set(x, vh + 7, z - 1, 0xFFFFFF);
                    continue;
                }
            }
        }
    }
}
