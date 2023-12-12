#version 450
#extension GL_ARB_gpu_shader_int64 : enable
#extension GL_ARB_bindless_texture: enable

layout(local_size_x = 32,  local_size_y = 32) in;

layout(rgba8, binding = 0) uniform image2D frameColor;

layout (binding = 8) uniform u_Camera {
    vec4 C_position;
    mat4 C_view;
    vec4 C_sun_dir;
    float fov;
    uint frameIndex;
};

#include assets/shaders/camera.glsl
#include assets/shaders/dda.glsl
#include assets/shaders/map.glsl
#include assets/shaders/rng.glsl

float vhash(vec4 p) {
    p = fract(p * 0.3183099 + 0.1) - fract(p + 23.22121);
    p = p * 17.0;
    return (fract(p.x * p.y * (1.0 - p.z) * p.w * (p.x + p.y + p.z + p.w)) - 0.5) * 2.0;
}


vec3 traceRay(vec3 rayO, in vec3 rayD, inout uint rng) {
    vec3 pixelColor = vec3(0.0);
    vec3 throughput = vec3(1.0);

    vec3 rayOrigin = rayO;
    vec3 rayDir = rayD;
    ivec3 mapPos;
    vec3 mask;
    float totalDistance;
    ivec3 rayStep;
    vec4 color;

    uint voxel;

    for (int bounceIdx = 0; bounceIdx <= 1; bounceIdx++) {
        voxel = traceMap(rayOrigin.xyz, rayDir.xyz, color, mask, mapPos, totalDistance, rayStep, bounceIdx == 0 ? 64 : 16);
        
        if (voxel == 0) {
            pixelColor += SkyDome(rayOrigin.xyz, rayDir.xyz).xyz * throughput;
            break;
        }

        rayOrigin = rayOrigin.xyz + rayDir.xyz * totalDistance + abs(mask) * 0.001;
        rayDir = normalize(mask + RandomUnitVector(rng));

        pixelColor += color.xyz  / 10.0;

        // throughput *= color.xyz;
    } 

    return pixelColor;
}

void main() {
    ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy);
    uint rngState = uint(uint(pixelCoords.x) * uint(1973) + uint(pixelCoords.y) * uint(9277) + frameIndex);

    ivec2 size = imageSize(frameColor);

    if (pixelCoords.x >= size.x || pixelCoords.y >= size.y) 
        return;

    vec2 rayUV = vec2(pixelCoords) / vec2(size) * 2.0 - 1.0;
    rayUV.y *= float(size.y) / float(size.x);
    
    // applying field of view
    rayUV *= tan(fov / 2);

    vec4 rayOrigin = C_position;
    vec4 rayDir = normalize(C_view * vec4(rayUV, 1.0, 1.0));

    // raybox intersection with the map bounding box.
    vec2 intersection = intersectAABB(rayOrigin.xyz, rayDir.xyz, vec3(0.), vec3(float(MAP_DIMENSION)));
    if (intersection.x < intersection.y) {
        vec3 volumeRayOrigin = rayOrigin.xyz + rayDir.xyz * max(intersection.x, 0) - EPSILON;
        vec3 color = traceRay(volumeRayOrigin.xyz, rayDir.xyz, rngState);

        vec4 prev = imageLoad(frameColor, pixelCoords);
        imageStore(frameColor, pixelCoords, mix(prev, vec4(color.xyz, 1.0), 1.0 / float(frameIndex)));
    }
}