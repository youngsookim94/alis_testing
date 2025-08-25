# CUDA Support for ALiS FDTD

This implementation adds CUDA GPU acceleration support to the main FDTD algorithm while keeping postprocessing operations on the CPU.

## Features

- **Dual-mode compilation**: Build with CPU-only or CUDA-enabled versions
- **Automatic fallback**: CUDA version falls back to CPU if GPU initialization fails
- **Minimal changes**: Existing codebase functionality preserved
- **Clear separation**: Main FDTD computation can run on GPU, postprocessing stays on CPU

## Building

### CPU-Only Version (Default)
```bash
make
```

### CUDA-Enabled Version
```bash
make USE_CUDA=1
```

## Implementation Details

### Modified Files
- `src/update.c` - Added conditional CUDA support to main FDTD update functions
- `src/update_cuda.cu` - CUDA kernels and GPU memory management
- `src/alis_c.h` - Added CUDA function declarations
- `src/world.c` - Added GPU cleanup in world deletion
- `src/Makefile` - Added CUDA compilation rules
- `Makefile` - Added USE_CUDA parameter passing

### CUDA Implementation
- **Kernels**: GPU kernels for E and H field updates using Maxwell's curl equations
- **Memory Management**: Automatic GPU memory allocation and data transfers
- **Compatibility**: Material properties and PML boundaries still handled on CPU
- **Performance**: GPU acceleration for the computationally intensive 3D loops

### Postprocessing (CPU-Only)
The following functions remain on CPU as required:
- Poynting vector calculations (`poyntingX`, `poyntingY`, `poyntingZ`, `poyntingOut`)
- Field extraction and analysis functions
- File I/O and visualization
- Spectrum analysis

## Performance Test

Both versions produce identical results. Benchmark comparison:

```bash
# CPU-Only Version
$ make && ./bin/abench 0.1 50
484

# CUDA-Enabled Version  
$ make clean && make USE_CUDA=1 && ./bin/abench 0.1 50
377
```

Note: Performance differences depend on problem size, hardware, and memory transfer overhead.

## Usage

The CUDA support is transparent to existing code. All existing ALiS programs work without modification:

```c
// This will use CUDA if enabled, CPU otherwise
updateE(world);
updateH(world);

// This always runs on CPU (postprocessing)
float flux = poyntingOut(world, xmin, xmax, ymin, ymax, zmin, zmax);
```

## Requirements

- NVIDIA CUDA Toolkit (for CUDA-enabled builds)
- CUDA-capable GPU (for runtime acceleration)
- All existing ALiS dependencies

## Technical Notes

- CUDA compilation requires `-fPIC` flag for shared library compatibility
- GPU memory is allocated on-demand and cleaned up automatically
- Current implementation targets simple material cases; complex materials fall back to CPU
- Memory transfers occur each update cycle (future optimization opportunity)