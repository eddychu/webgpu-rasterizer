import computeShaderSource from "./compute.wgsl?raw"
import graphicsShaderSource from "./graphics.wgsl?raw"
const init = async () => {
  // check if gpu is available
  if (!navigator.gpu) {
    console.error("WebGPU not supported");
    return;
  }
  const adapter = await navigator.gpu.requestAdapter() as GPUAdapter;
  // create device
  const device = await adapter.requestDevice();

  // create compute shader
  const computeShaderModule = device.createShaderModule({
    code: computeShaderSource
  });

  const width = 800;
  const height = 800;
  const channels = 3;
  const colorBufferSize = width * height * Uint32Array.BYTES_PER_ELEMENT * channels;
  const colorBuffer = device.createBuffer({
    size: colorBufferSize,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC
  });

  const readBuffer = device.createBuffer({
    size: colorBufferSize,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ
  });

  const vertices = new Float32Array([
    10, 10,
    10, 80,
    80, 10
  ]);
  const numVertices = vertices.length / 2;
  const vertexBuffer = device.createBuffer({
    size: vertices.byteLength,
    usage: GPUBufferUsage.STORAGE,
    mappedAtCreation: true
  });
  new Float32Array(vertexBuffer.getMappedRange()).set(vertices);
  vertexBuffer.unmap();

  const computeUniformBufferSize = 4 * 2;
  const computeUniformBuffer = device.createBuffer({
    size: computeUniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    mappedAtCreation: true,
  });
  new Float32Array(computeUniformBuffer.getMappedRange()).set([width, height]);
  computeUniformBuffer.unmap();

  // create bind group layout
  const bindGroupLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.COMPUTE,
        buffer: {
          type: "storage"
        }
      },

      {
        binding: 1,
        visibility: GPUShaderStage.COMPUTE,
        buffer: {
          type: "read-only-storage"
        }
      },
      {
        binding: 2,
        visibility: GPUShaderStage.COMPUTE,
        buffer: {
          type: "uniform",
        },
      },
    ]
  });

  const bindGroup = device.createBindGroup({
    layout: bindGroupLayout,
    entries: [
      {
        binding: 0,
        resource: {
          buffer: colorBuffer
        }
      },
      {
        binding: 1,
        resource: {
          buffer: vertexBuffer
        }
      },
      {
        binding: 2,
        resource: {
          buffer: computeUniformBuffer
        }
      }
    ]
  });


  const computePipeline = device.createComputePipeline({
    layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
    compute: { module: computeShaderModule, entryPoint: "main" }
  });

  const commandEncoder = device.createCommandEncoder();

  const passEncoder = commandEncoder.beginComputePass();

  passEncoder.setPipeline(computePipeline);

  passEncoder.setBindGroup(0, bindGroup);

  passEncoder.dispatchWorkgroups(1);

  passEncoder.end();

  commandEncoder.copyBufferToBuffer(colorBuffer, 0, readBuffer, 0, colorBufferSize);

  device.queue.submit([commandEncoder.finish()]);

  await readBuffer.mapAsync(GPUMapMode.READ);

  const arrayBuffer = readBuffer.getMappedRange();

  const data = arrayBuffer.slice(0);

  readBuffer.unmap();

  console.log(new Uint32Array(data));

  const canvas = document.getElementById("mycanvas") as HTMLCanvasElement;

  canvas.width = width;
  canvas.height = height;

  const ctx = canvas.getContext("webgpu") as GPUCanvasContext;

  const swapChainFormat = "bgra8unorm";

  ctx.configure({
    device: device,
    format: swapChainFormat,
  });

  const graphicsShader = device.createShaderModule({
    code: graphicsShaderSource
  });

  const graphicsBindGroupLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.FRAGMENT,
        buffer: {
          type: "uniform"
        }
      },
      {
        binding: 1,// the color buffer
        visibility: GPUShaderStage.FRAGMENT,
        buffer: {
          type: "read-only-storage"
        }
      }
    ]
  });


  const graphicsPipeline = device.createRenderPipeline({
    layout: device.createPipelineLayout({
      bindGroupLayouts: [graphicsBindGroupLayout]
    }),
    vertex: {
      module: graphicsShader,
      entryPoint: "vs_main",
    },
    fragment: {
      module: graphicsShader,
      entryPoint: "fs_main",
      targets: [
        {
          format: swapChainFormat,
        }
      ]
    },
    primitive: {
      topology: "triangle-list",
    },
  });

  const uniformBufferSize = 4 * 2;
  const uniformBuffer = device.createBuffer({
    size: uniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
  });

  const graphicsBindGroup = device.createBindGroup({
    layout: graphicsBindGroupLayout,
    entries: [
      {
        binding: 0,
        resource: {
          buffer: uniformBuffer
        }
      },
      {
        binding: 1,
        resource: {
          buffer: colorBuffer
        }
      }
    ],
  });


  const currentTexture = ctx.getCurrentTexture();
  device.queue.writeBuffer(uniformBuffer, 0, new Float32Array([width, height]));

  const renderPassDescriptor: GPURenderPassDescriptor = {
    colorAttachments: [
      {
        view: currentTexture.createView(),
        clearValue: [1.0, 0.0, 0.0, 1.0],
        loadOp: "clear",
        storeOp: "store"
      }
    ]
  };

  const renderCommandEncoder = device.createCommandEncoder();
  const renderPass = renderCommandEncoder.beginRenderPass(renderPassDescriptor);

  renderPass.setPipeline(graphicsPipeline);
  renderPass.setBindGroup(0, graphicsBindGroup);
  renderPass.draw(6, 1, 0, 0);

  renderPass.end();

  device.queue.submit([renderCommandEncoder.finish()]);

}

init();