import { mat4 } from "gl-matrix";
import computeShaderSource from "./compute.wgsl?raw"
import graphicsShaderSource from "./graphics.wgsl?raw"
import { TypedArray, WebIO } from '@gltf-transform/core';
const loadModel = async (url: string) => {
  const io = new WebIO({ credentials: 'include' });
  const document = await io.read(url);
  const model = document.getRoot();
  const positions = model.listMeshes()[0].listPrimitives()[0].getAttribute('POSITION')?.getArray() as Float32Array;
  const uvs = model.listMeshes()[0].listPrimitives()[0].getAttribute('TEXCOORD_0')?.getArray() as Float32Array;
  const normals = model.listMeshes()[0].listPrimitives()[0].getAttribute('NORMAL')?.getArray() as Float32Array;
  const indices = model.listMeshes()[0].listPrimitives()[0].getIndices()?.getArray() as TypedArray;

  return [
    positions,
    normals,
    uvs,
    new Uint32Array(indices)
  ];
}

await loadModel("public/helmet/DamagedHelmet.gltf");


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
  const colorBufferData = new Uint32Array(width * height * channels);
  const colorBuffer = device.createBuffer({
    size: colorBufferSize,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST
  });

  const depthBufferData = new Uint32Array(width * height);
  const depthBuffer = device.createBuffer({
    size: depthBufferData.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
  });

  // initialize depth buffer with max value of u32


  const readBuffer = device.createBuffer({
    size: colorBufferSize,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ
  });

  // const vertices = new Float32Array([
  //   -0.5, -0.5, 0.0,
  //   0.5, -0.5, 0.0,
  //   0.0, 0.5, 0.0
  // ]);
  const [vertices, normals, uvs, indices] = await loadModel("public/helmet/DamagedHelmet.gltf");
  console.log(indices);
  const numVertices = vertices.length / 3;
  const vertexBuffer = device.createBuffer({
    size: vertices.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });
  // new Float32Array(vertexBuffer.getMappedRange()).set(vertices);
  // vertexBuffer.unmap();

  device.queue.writeBuffer(vertexBuffer, 0, vertices);

  const indexBuffer = device.createBuffer({
    size: indices.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });

  device.queue.writeBuffer(indexBuffer, 0, indices);

  const uvBuffer = device.createBuffer({
    size: uvs.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });

  device.queue.writeBuffer(uvBuffer, 0, uvs);

  const normalBuffer = device.createBuffer({
    size: normals.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  })
  device.queue.writeBuffer(normalBuffer, 0, normals);

  const viewMatrix = mat4.create();
  const projectionMatrix = mat4.create();
  const modelMatrix = mat4.create();
  const mvp = mat4.create();
  mat4.lookAt(viewMatrix, [0, 0, 3], [0, 0, 0], [0, 1, 0]);

  mat4.perspective(projectionMatrix, Math.PI / 2, 1, 0.1, 100);



  mat4.multiply(mvp, projectionMatrix, viewMatrix);


  // a 4 * 16 matrix for the projection matrix
  // a 4 * 2 for the width and height
  // a 8 for the padding requirement
  const computeUniformBufferSize = 4 * 16 + 4 * 2 + 8;
  const computeUniformBuffer = device.createBuffer({
    size: computeUniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });



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
      {
        binding: 3,
        visibility: GPUShaderStage.COMPUTE,
        buffer: {
          type: "read-only-storage",
        },
      },
      {
        binding: 4,
        visibility: GPUShaderStage.COMPUTE,
        buffer: {
          type: "read-only-storage",
        },
      },
      {
        binding: 5,
        visibility: GPUShaderStage.COMPUTE,
        buffer: {
          type: "read-only-storage",
        },
      },
      {
        binding: 6,
        visibility: GPUShaderStage.COMPUTE,
        buffer: {
          type: "storage",
        },
      }
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
      },
      {
        binding: 3,
        resource: {
          buffer: indexBuffer
        }
      },
      {
        binding: 4,
        resource: {
          buffer: uvBuffer
        }
      },
      {
        binding: 5,
        resource: {
          buffer: normalBuffer,
        }
      },
      {
        binding: 6,
        resource: {
          buffer: depthBuffer,
        }
      }
    ]
  });




  const computePipeline = device.createComputePipeline({
    layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
    compute: { module: computeShaderModule, entryPoint: "main" }
  });


  const canvas = document.getElementById("mycanvas") as HTMLCanvasElement;

  canvas.width = width;
  canvas.height = height;

  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;

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



  let frames = 0;
  const render = () => {
    frames++;

    colorBufferData.fill(0);
    device.queue.writeBuffer(colorBuffer, 0, colorBufferData);

    depthBufferData.fill(4294967295);

    device.queue.writeBuffer(depthBuffer, 0, depthBufferData);
    mat4.rotateY(modelMatrix, mat4.create(), 0.01);

    mat4.multiply(mvp, mvp, modelMatrix);

    const uniformData = new Float32Array([...mvp, width, height, 0, 0]);

    device.queue.writeBuffer(computeUniformBuffer, 0, uniformData);

    const commandEncoder = device.createCommandEncoder();

    const passEncoder = commandEncoder.beginComputePass();

    passEncoder.setPipeline(computePipeline);

    passEncoder.setBindGroup(0, bindGroup);

    passEncoder.dispatchWorkgroups(Math.ceil(indices.length / 3 / 256));

    passEncoder.end();

    commandEncoder.copyBufferToBuffer(colorBuffer, 0, readBuffer, 0, colorBufferSize);

    device.queue.submit([commandEncoder.finish()]);

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

    requestAnimationFrame(render);
  }




  // wait for the GPU to finish

  // await readBuffer.mapAsync(GPUMapMode.READ);

  // const arrayBuffer = readBuffer.getMappedRange();

  // const data = arrayBuffer.slice(0);

  // readBuffer.unmap();

  // console.log(new Uint32Array(data));


  render();

}

init();