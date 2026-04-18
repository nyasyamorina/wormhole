mkdir -p zig-out

mkdir -p zig-out/shaders
rm -f zig-out/shaders/*
slangc src/shaders/init_ray.slang -o zig-out/shaders/init_ray.spv -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry main
slangc src/shaders/iter_ray.slang -o zig-out/shaders/iter_ray.spv -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry main
slangc src/shaders/render_ray.slang -o zig-out/shaders/render_ray.spv -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry main


mkdir -p zig-out/packs

zig build --release=small
rm -f zig-out/packs/schwarzschild-linux-x86_64-pack.tar.xz
tar -O -c readme.md readme.zh.md -C zig-out/bin -c schwarzschild -C ../shaders -c init_ray.spv iter_ray.spv render_ray.spv | xz -zc9e - > zig-out/packs/schwarzschild-linux-x86_64-pack.tar.xz

zig build --release=small -Dtarget=x86_64-windows # this line should be run on windows
rm -f zig-out/packs/schwarzschild-windows-x86_64-pack.tar.xz
tar -O -c readme.md readme.zh.md -C pack-stuff/windows -c glfw3.dll -C ../../zig-out/bin -c schwarzschild.exe -C ../shaders -c init_ray.spv iter_ray.spv render_ray.spv | xz -zc9e - > zig-out/packs/schwarzschild-windows-x86_64-pack.tar.xz
