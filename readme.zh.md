# 一个可交互的史瓦西黑洞模拟

---

## 基础用法

1. 前往 [莉莉丝页面](https://github.com/nyasyamorina/wormhole/releases) 里下载 `schwarzschild-windows-x86_64-pack.tar.xz`（linux 用户为 `schwarzschild-linux-x86_64-pack.tar.xz`），

2. 解压到任意文件夹并运行 `schwarzschild.exe`（linux 用户为 `schwarzschild`）。

    linux 用户需要在系统里安装 glfw3。

---

## 系统要求

- glfw 3.4 和 vulkan 1.3 兼容性（人话说就是有2022年之后显卡驱动更新的电脑）。

---

## 操作

- 移动镜头：移动鼠标，

- 移动（加速）：`WASD` 前左后右，`ctrl` 下，`空格` 上，

- 调整推力：鼠标滚轮，

- 退出：`q`。

---

## 数值

当程序在命令行终端里打开时，终端里会显示一系列数值：

 - `center object mass`：黑洞的质量，
 - `schwarzschild radius`：黑洞的史瓦西半径（为了方便计算，在这里史瓦西半径取值为 1 光秒），
 - `your perspective`：“玩家”视角，也就是你，
 - `distant perspective`：远距离观察者视角*，因为外部观察者永远无法观测黑洞内部，当“玩家”坠入黑洞后，相关数值会变为 nan，
 - `time`：从模拟开始经过的时间，
 - `speed`：“玩家”的速度，
 - `movement thrust`：“玩家”移动时的推力（加速度），
 - `radial position`：“玩家”到洞奇点的距离，
 - `radial speed`：“玩家”与黑洞奇点的相对运动，正值为“玩家”远离奇点，负值为“玩家”靠近奇点，
 - `angular speed`：“玩家”围绕黑洞的（线/角）速度，

    *：远距离观察者视角的数值只是把模拟结果放到史瓦西坐标系里重新解释，也就是说这些数值不是“玩家”看到或者远距离观察者看到的，所以这些数值与“玩家”是不存在因果关系的。

---

## 画面真实性

### 天球

- 天球假设静态并且距“玩家”无限远，也就是说无论移动多快还是时间经过多久，天球本身是不会变化的。

- 天球是由自制的（效果稀烂的）算法生成的，移动时星体会非常闪烁，而且接近光速运动时仍然会有大片区域保持黑暗。

    为了计算光的多普勒效应，天球需要提供“全频”光谱辐射率，或者，在这里实现里是使用亮度和色温计算黑体辐射。

    使用现实数据作为天球渲染是可能的（见 [我的文章](https://zhuanlan.zhihu.com/p/600600997)），但这会使莉莉丝变得巨大，程序变得复杂，还有版权什么的。

### 后处理

- 炫光：炫光算法是只基于视觉表现做的，并不是准确的物理过程，这个算法灵感来自 sonicether 的[这里](https://www.shadertoy.com/view/lstSRS)，

- 自动曝光：做了。

    需要注意的是，以接近光速运动时，整个场景的亮度会跨越多个数量级，而这里实现的炫光和自动曝光并不能很好地处理这种情况。

    **请求更好的炫光和自动曝光算法**

### 数值模拟

“玩家”运动和光线追踪都是使用数值求解微分方程，所以不可避免地会出现数值误差（来自有限模拟和浮点数误差）。具体表现为：

 - 运动模拟会在“玩家”距离黑洞奇点约 0.07x 史瓦西半径时停止，因为更靠近奇点会导致数值发散至 nan，

 - 运动模拟是不稳定的，特别是初始状态选取圆形轨道（见下），长时间运行最终会坠入黑洞，

 - 当玩家距离黑洞太远时天球渲染会出现不连续间断，这是由动态选取光线步长造成的，

 - 当玩家太靠近黑洞奇点时，黑色区域（黑洞的影子）边缘可能会出现蓝色条带，因为当光线由于有限模拟未能逃离“强引力区域”时，把这些光线渲染成蓝色作为警告。

---

## 进阶用法

程序本身（`schwarzschild.exe` 或 `schwarzschild`）是不足以运行的，还需要提供外部的着色器文件，由此用户可以提供自定义着色器。在空白文件夹里以无启动参数运行程序会生成这里使用的着色器（见下）。

### 参数

- `-s="path/to/shaders"` 或 `--shader="path/to/shaders"`：指定着色器文件夹，文件夹里必须存在着色器文件（见下），默认为当前运行路径。

- `--slangc="path/to/slangc"`: 指定 slang 编译器路径（见下），默认值："slangc"。

- `-f=<>` 或 `--fov=<>`: 指定视场角大小（垂直），单位：角度，默认值：60。

- `-p=<>` 或 `--posotion=<>`: 指定一开始距离黑洞奇点多远，这个数值的有效性与 `--init-state` 有关，单位：史瓦西半径，默认值：100。

- `-i=<>` 或 `--init-state=<>`: 指定一开始“玩家”的运动状态，默认值：`at_rest`：

    - `at_rest`：静止，一开始“玩家”与黑洞保持相对静止，并且逐渐向黑洞加速，`--posotion` 必须大于 1，

    - `circular_orbit`：圆形轨道，“玩家”将处于一个稳定的圆形轨道上绕着黑洞转圈圈，`--position` 必须大于 1.5。

- `--simulation-speed=<>`: 控制模拟时间速度与现实时间速度的比例，默认值：1。

- `--simulation-sub-steps=<>`：控制运动模拟的精度，数值越大精度越高，但 CPU 使用率也会越高，默认值：100。

- `--iter-per-call=<>`: 控制每次调用 `iter_ray`（见下）时光线追踪的计算次数，数值越大渲染结果越准确，但 GPU 使用率也会越高，默认值：500。

---

## 着色器

### 文件和编译

在 shader 文件夹里（`--shader`）放置 `init_ray`, `iter_ray`， `render_ray`, `post_process_1`, `post_process_2` 和 `final` 这几个着色器，
程序会优先使用 spirv 着色器（文件后缀 `.spv`），如果不存在则会寻找 slang 着色器（文件后缀 `.slang`）并自动调用 slangc（`--slangc`）编译，
如果还是找不到，程序会自动生成默认的 slang 着色器文件（自动生成会多一个没有入口函数的 `utils.slang` 文件）。

### 布局

所有着色器都可以访问 1 个 `uniform` 结构体和 4 个图像缓冲区，而 `final` 着色器可以额外访问交换链图像（下一个显示帧）。

uniform 和图像缓冲区用 slang 写为：

```slang
[vk_binding(0, 0)] ConstantBuffer<Uniform> uniform;

[vk_binding(0, 1)] RWTexture2D<float4, 1> tex_0;
[vk_binding(1, 1)] RWTexture2D<float4, 1> tex_1;
[vk_binding(2, 1)] RWTexture2D<float4, 1> tex_2;
[vk_binding(3, 1)] RWTexture2D<float4, 1> tex_3;
```

其中 uniform 结构为：

```slang
struct SpaceTimeFrame {
    float4 position;
    float4 axis_x;
    float4 axis_y;
    float4 axis_z;
    float4 axis_t;
};
struct Uniform {
    SpaceTimeFrame frame;
    float2 screen_scale;
    uint iter_per_call;
    uint mipmap_levels;
};
```

交换链图像为：

```slang
[vk_binding(0, 2)] [format("rgba8")] RWTexture2D<float4> surface;
```

所有着色器都必须有以下入口函数：

```slang
[shader("compute")] [numthreads(16, 16, 1)]
void main(uint3 thread_id: SV_DispatchThreadID) { /* ... */ }
```

### 流程

尽管着色器是可以自定义的，但是计算（渲染）流程是固定的。以下是流程顺序以及默认的实现功能：

1. `init_ray`：初始光线，

2. `iter_ray`：求解（追踪）光线，

3. `render_ray`：渲染光线到 `[vk_binding(3, 1)]` 图像里，

4. （固定阶段）清空 `[vk_binding(2, 1)]` 并在里面构建 `[vk_binding(3, 1)]` 的 mipmap，

5. `post_process_1`：把高斯模糊作用到 mipmap 里（横向），

6. `post_process_2`：把高斯模糊作用到 mipmap 里（竖向），

7. `final`：渲染最终结果到交换链图像里。

其中 mipmap 层数从 0 开始，总共 `uniform.mipmap_levels` 层，每层的坐标偏移及大小由以下方法计算：

```slang
uint2 mipmapOffset(uint2 extent, uint level) {
    uint2 box_offset;
    if ((level & 1) == 0) {
        box_offset = {extent.x >> (level / 2 + 1), 0};
    } else {
        box_offset = {0, extent.y >> ((level + 1) / 2)};
    }
    uint2 box_extent = {
        max(1, extent.x >> (level / 2 + 1)),
        max(1, extent.y >> ((level + 1) / 2)),
    };

    uint2 mm_extent = mipmapExtent(extent, level);
    return {
        box_offset.x + (box_extent.x - mm_extent.x) / 2,
        box_offset.y + (box_extent.y - mm_extent.y) / 2,
    };
}

uint2 mipmapExtent(uint2 extent, uint level) {
    return {
        max(1, extent.x >> (level + 1)),
        max(1, extent.y >> (level + 1)),
    };
}
```

---

## 问题反馈

请在仓库里开 issue。
