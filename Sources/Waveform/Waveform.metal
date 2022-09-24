
#include <metal_stdlib>
using namespace metal;

kernel void waveform_bin(device const float* in,
                         device float* out_min,
                         device float* out_max,
                         constant uint& count,
                         uint tid [[ thread_position_in_grid]]) {
    
    if(tid >= count) {
        return;
    }
    
    auto a = in[tid*2];
    auto b = in[tid*2+1];
    out_min[tid] = min(a, b);
    out_max[tid] = max(a, b);
}

struct FragIn {
    float4 position [[ position ]];
    float2 uv; // unit square UV coordinates
};


constant float2 pos[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1 } };
constant float2 uv[4] = { {0, -1}, {1, -1}, {0,1}, {1,1 } };

vertex FragIn waveform_vert(uint id [[ vertex_id ]]) {
    FragIn out;
    out.position = float4(pos[id], 0, 1);
    out.uv = uv[id];
    return out;
}

struct Constants {
    
};

float sample_waveform(device const float* min_waveform,
                      device const float* max_waveform,
                      uint count,
                      float2 uv) {

    int x = clamp(int(count * uv.x), 0, int(count));

    auto min_value = min_waveform[x];
    auto max_value = max_waveform[x];

    return (uv.y > min_value && uv.y < max_value) ? 1.0 : 0.0;
}

fragment half4 waveform_frag(FragIn in   [[ stage_in ]],
                             device const float* min_waveform,
                             device const float* max_waveform,
                             constant uint& count,
                             constant Constants& constants) {

    half s = sample_waveform(min_waveform, max_waveform, count, in.uv);
    
    return {s,s,s,1.0};

}
