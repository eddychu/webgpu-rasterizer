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
@group(0) @binding(6) var<storage, read_write> depthBuffer: array<f32>;
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
  return vec4<f32>(v.x / v.w, v.y / v.w, v.z / v.w, v.w);
}

fn viewport(v: vec4<f32>) -> vec4<f32> {
  let x = (v.x + 1.0) * uniforms.screenWidth / 2.0;
  let y = (1.0 - v.y) * uniforms.screenHeight / 2.0;
  return vec4<f32>(x, y, v.z, v.w);
}

fn is_back(v1: vec2<f32>, v2: vec2<f32>, v3: vec2<f32>) -> bool {


  let v1v2 = v2 - v1;
  let v2v3 = v3 - v2;

  let cross = v1v2.x * v2v3.y - v1v2.y * v2v3.x;

  // return cross < 0.0;
  return false;
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

  let v1s = viewport(perspective_divide(vertex(point1)));
  let v2s = viewport(perspective_divide(vertex(point2)));
  let v3s = viewport(perspective_divide(vertex(point3)));

  if (!is_back(v1s.xy, v2s.xy, v3s.xy)) {
    let minX = min(v1s.x, min(v2s.x, v3s.x));
    let minY = min(v1s.y, min(v2s.y, v3s.y));
    let maxX = max(v1s.x, max(v2s.x, v3s.x));
    let maxY = max(v1s.y, max(v2s.y, v3s.y));

    for (var x = u32(floor(minX)); x < u32(ceil(maxX)); x = x + 1) {
      for (var y = u32(floor(minY)); y < u32(ceil(maxY)); y = y + 1) {
        let p = vec2<f32>(f32(x) + 0.5, f32(y) + 0.5);
        let bc = barycentric(vec2<f32>(v1s.x, v1s.y), vec2<f32>(v2s.x, v2s.y), vec2<f32>(v3s.x, v3s.y), p);
        if (bc.x < 0.0 || bc.y < 0.0 || bc.z < 0.0) {
          continue;
        }
        let depth = v1s.z * bc.x + v2s.z * bc.y + v3s.z * bc.z;
        let depth_index = y * u32(uniforms.screenWidth) + x;
        if (depth > depthBuffer[depth_index]) {
          continue;
        }
        depthBuffer[depth_index] = depth;

        // interpolate normal
        let n = normal1_vec * bc.x + normal2_vec * bc.y + normal3_vec * bc.z;
        let r = u32(n.x * 255.0);
        let g = u32(n.y * 255.0);
        let b = u32(n.z * 255.0);

        draw_pixel(x, y, r, g, b);
      }
    }
  }

  

  // let v1 = vec2<f32>(v1s.x, v1s.y);
  // let v2 = vec2<f32>(v2s.x, v2s.y);
  // let v3 = vec2<f32>(v3s.x, v3s.y);

  // draw_line(v1, v2);
  // draw_line(v2, v3);
  // draw_line(v3, v1);
}