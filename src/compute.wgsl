struct ColorBuffer{
  values: array<u32>
};

struct Vertex {
  x: f32,
  y: f32,
};

struct VertexBuffer {
  values: array<Vertex>
};

struct Uniform {
    screenWidth: f32,
    screenHeight: f32
};

// this is the final output buffer from our shader.
@group(0) @binding(0) var<storage, read_write> color_buffer: ColorBuffer;
@group(0) @binding(1) var<storage, read> vertexBuffer: VertexBuffer;
@group(0) @binding(2) var<uniform> uniforms: Uniform;
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

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let index = global_id.x * 3;
  let point1 = vertexBuffer.values[index];
  let point2 = vertexBuffer.values[index + 1];
  let point3 = vertexBuffer.values[index + 2];

  let v1 = vec2<f32>(point1.x, point1.y);
  let v2 = vec2<f32>(point2.x, point2.y);
  let v3 = vec2<f32>(point3.x, point3.y);

  draw_line(v1, v2);
  draw_line(v2, v3);
  draw_line(v3, v1);
}