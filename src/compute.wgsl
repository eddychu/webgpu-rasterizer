struct ColorBuffer{
  values: array<u32>
};

struct Vertex {
  x: f32,
  y: f32,
  z: f32, 
};

struct VertexBuffer {
  values: array<Vertex>
};

struct UV {
  u: f32,
  v: f32
};

struct UVBuffer {
  values: array<UV>
};

// struct NormalBuffer {
//   values: array<Vertex>
// };

struct Uniform {
    mvp: mat4x4<f32>,
    screenWidth: f32,
    screenHeight: f32
};

// this is the final output buffer from our shader.
@group(0) @binding(0) var<storage, read_write> color_buffer: ColorBuffer;
@group(0) @binding(1) var<storage, read> vertexBuffer: VertexBuffer;
@group(0) @binding(2) var<uniform> uniforms: Uniform;
@group(0) @binding(3) var<storage, read> indexBuffer: array<u32>;
@group(0) @binding(4) var<storage, read> uvBuffer: array<vec2<f32>>;
@group(0) @binding(5) var<storage, read> normalBuffer: VertexBuffer;
@group(0) @binding(6) var<storage, read_write> depthBuffer: array<atomic<u32>>;
// this is the uniform buffer that we will pass to the shader.


fn draw_pixel(x: u32, y: u32, r: u32, g: u32, b: u32) {
  let index = u32(x + y * u32(uniforms.screenWidth)) * 3;
  color_buffer.values[index] = r;
  color_buffer.values[index + 1] = g;
  color_buffer.values[index + 2] = b;
}


// bresenham's line algorithm
fn draw_line(v1: vec2<f32>, v2: vec2<f32>) {
  let dx = v2.x - v1.x;
  let dy = v2.y - v1.y;

  let steps = max(abs(dx), abs(dy));

  let x_increment = dx / steps;
  let y_increment = dy / steps;

  for(var i = 0u; i < u32(steps); i = i + 1) {
    let x = u32(v1.x + f32(i) * x_increment);
    let y = u32(v1.y + f32(i) * y_increment);
    draw_pixel(x, y, 255, 255, 255);
  }
}

fn vertex(v: Vertex) -> vec4<f32> {
  return uniforms.mvp * vec4<f32>(v.x, v.y, v.z, 1.0);
} 

fn perspective_divide(v: vec4<f32>) -> vec4<f32> {
  return vec4<f32>(v.x / v.w, v.y / v.w, v.z / v.w, 1.0 / v.w);
}

fn viewport(v: vec4<f32>) -> vec4<f32> {
  let x = (v.x + 1.0) * uniforms.screenWidth / 2.0;
  let y = (1.0 - v.y) * uniforms.screenHeight / 2.0;
  return vec4<f32>(x, y, v.z, v.w);
}

fn not_clipped(v1: vec4<f32>, v2: vec4<f32>, v3: vec4<f32>) -> bool {
  
  let inside1 = v1.x >= -v1.w && v1.x <= v1.w && v1.y >= -v1.w && v1.y <= v1.w && v1.z >= 0 && v1.z <= v1.w;
  let inside2 = v2.x >= -v2.w && v2.x <= v2.w && v2.y >= -v2.w && v2.y <= v2.w && v2.z >= 0 && v2.z <= v2.w;
  let inside3 = v3.x >= -v3.w && v3.x <= v3.w && v3.y >= -v3.w && v3.y <= v3.w && v3.z >= 0 && v3.z <= v3.w;

  return inside1 && inside2 && inside3;
} 

fn is_back(v1: vec2<f32>, v2: vec2<f32>, v3: vec2<f32>) -> bool {

  let xa = v1.x;
  let xb = v2.x;
  let xc = v3.x;

  let ya = v1.y;
  let yb = v2.y;
  let yc = v3.y;

  return xa * (yb - yc) + xb * (yc - ya) + xc * (ya - yb) >= 0.0;
}

fn barycentric(a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, p: vec2<f32>) -> vec3<f32> {
    let v0 = b - a;
    let v1 = c - a;
    let v2 = p - a; 

    let d00 = dot(v0, v0);
    let d01 = dot(v0, v1);
    let d11 = dot(v1, v1);
    let d20 = dot(v2, v0);
    let d21 = dot(v2, v1);

    let denom = d00 * d11 - d01 * d01;

    let v = (d11 * d20 - d01 * d21) / denom;
    let w = (d00 * d21 - d01 * d20) / denom;
    let u = 1.0 - v - w;

    return vec3<f32>(u, v, w);
}

fn perspective_correct_barycentric(bc: vec3<f32>, w: vec3<f32>) -> vec3<f32> {
  let numerator = vec3<f32>(bc.x / w.x, bc.y / w.y, bc.z / w.z);
  let denominator = numerator.x + numerator.y + numerator.z;
  return vec3<f32>(numerator.x / denominator, numerator.y / denominator, numerator.z / denominator);
}

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let index = global_id.x * 3;
  let index1 = indexBuffer[index];
  let index2 = indexBuffer[index + 1];
  let index3 = indexBuffer[index + 2];

  // color_buffer.values[index] = index1;
  // color_buffer.values[index + 1] = index2;
  // color_buffer.values[index + 2] = index3;


  let point1 = vertexBuffer.values[index1];
  let point2 = vertexBuffer.values[index2];
  let point3 = vertexBuffer.values[index3];

  let uv1 = uvBuffer[index1];
  let uv2 = uvBuffer[index2];
  let uv3 = uvBuffer[index3];

  var normal1 = normalBuffer.values[index1];
  var normal2 = normalBuffer.values[index2];
  var normal3 = normalBuffer.values[index3];

  var normal1_vec = vec3<f32>(normal1.x, normal1.y, normal1.z);
  var normal2_vec = vec3<f32>(normal2.x, normal2.y, normal2.z);
  var normal3_vec = vec3<f32>(normal3.x, normal3.y, normal3.z);

  normal1_vec = normal1_vec * 0.5 + 0.5;
  normal2_vec = normal2_vec * 0.5 + 0.5;
  normal3_vec = normal3_vec * 0.5 + 0.5;

  let clip_coord1 = vertex(point1);
  let clip_coord2 = vertex(point2);
  let clip_coord3 = vertex(point3);

  if (!not_clipped(clip_coord1, clip_coord2, clip_coord3)) {
    return;
  }

  let v1s = viewport(perspective_divide(clip_coord1));
  let v2s = viewport(perspective_divide(clip_coord2));
  let v3s = viewport(perspective_divide(clip_coord3));

  if (!is_back(v1s.xy, v2s.xy, v3s.xy)) {
    let minX = min(v1s.x, min(v2s.x, v3s.x));
    let minY = min(v1s.y, min(v2s.y, v3s.y));
    let maxX = max(v1s.x, max(v2s.x, v3s.x));
    let maxY = max(v1s.y, max(v2s.y, v3s.y));

    for (var x = u32(floor(minX)); x < u32(ceil(maxX)); x = x + 1) {
      for (var y = u32(floor(minY)); y < u32(ceil(maxY)); y = y + 1) {
        let p = vec2<f32>(f32(x) + 0.5, f32(y) + 0.5);
        var bc = barycentric(vec2<f32>(v1s.x, v1s.y), vec2<f32>(v2s.x, v2s.y), vec2<f32>(v3s.x, v3s.y), p);
        if (bc.x < 0.0 || bc.y < 0.0 || bc.z < 0.0) {
          continue;
        }
        // convert barycentric coordiante to perspective correct one
        bc = perspective_correct_barycentric(bc, vec3<f32>(v1s.w, v2s.w, v3s.w));
        let depth = v1s.z * bc.x + v2s.z * bc.y + v3s.z * bc.z;
        // convert depth to u32 by multiplying max of u32
        let depth_uint = u32(floor(depth * 4294967296.0));
        let depth_index = y * u32(uniforms.screenWidth) + x;

        let ret_depth = atomicMin(&depthBuffer[depth_index], depth_uint);

        if ret_depth <= depth_uint {
          continue;
        }
        let n = normal1_vec * bc.x + normal2_vec * bc.y + normal3_vec * bc.z;
        let r = u32(n.x * 255.0);
        let g = u32(n.y * 255.0);
        let b = u32(n.z * 255.0);
        draw_pixel(x, y, r, g, b);
      }
    }
  }
}