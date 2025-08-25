/**********************************************************************
 * ALiS is Copyright (C) 2009-2019 by Ho-Seok Ee <hsee@kongju.ac.kr>. *
 * Redistribution and use with or without modification, are permitted *
 * under the terms of the Artistic License version 2.                 *
 **********************************************************************/

#include <cuda_runtime.h>
#include <device_launch_parameters.h>

// Forward declarations to avoid header conflicts
typedef struct world_s *world;
typedef struct {
    float ***x, ***y, ***z;
    float ***yMinPx, ***zMinPx, ***xMinPy, ***zMinPy, ***xMinPz, ***yMinPz;
    float ***yMaxPx, ***zMaxPx, ***xMaxPy, ***zMaxPy, ***xMaxPz, ***yMaxPz;
    float *****Jx, *****Jy, *****Jz, *****Kx, *****Ky, *****Kz;
    float t;
} vfield;

typedef struct {
    float *dx, *dy, *dz, *dtdx, *dtdy, *dtdz;
    float *xP, *yP, *zP, *xPy, *xPz, *yPz, *yPx, *zPx, *zPy;
    float ***x, ***y, ***z;
    float ****Jx, ****Jy, ****Jz;
    float *ax, *ay, *az;
    float **JJx, **JJy, **JJz, **JKx, **JKy, **JKz, **JEx, **JEy, **JEz;
    float **KJx, **KJy, **KJz, **KKx, **KKy, **KKz, **KEx, **KEy, **KEz;
    int N, *NJ, *NK, *iMin, *iMax, *jMin, *jMax, *kMin, *kMax;
    void *O;
    void *M;
} coeffs;

struct world_s {
    float t, dt, dx, dy, dz, eV, f;
    float xMin, xMax, yMin, yMax, zMin, zMax;
    float xMIN, xMAX, yMIN, yMAX, zMIN, zMAX;
    int iMin, iMax, iNum, jMin, jMax, jNum, kMin, kMax, kNum;
    int iMIN, iMAX, iNUM, jMIN, jMAX, jNUM, kMIN, kMAX, kNUM;
    // ... other fields would be here but we only need the sizing info
};

// CUDA kernels for FDTD update

__global__ void updateF_kernel(
    float *Fx, float *Fy, float *Fz,
    float *Gx, float *Gy, float *Gz,
    float *Cx, float *Cy, float *Cz,
    float *dtdx, float *dtdy, float *dtdz,
    int Alt, int iMin, int iMax, int jMin, int jMax, int kMin, int kMax,
    int iNum, int jNum, int kNum)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x + iMin;
    int j = blockIdx.y * blockDim.y + threadIdx.y + jMin;
    int k = blockIdx.z * blockDim.z + threadIdx.z + kMin;
    
    if (i <= iMax && j <= jMax && k <= kMax) {
        int idx = i * jNum * kNum + j * kNum + k;
        int idx_iAlt = (i + Alt) * jNum * kNum + j * kNum + k;
        int idx_jAlt = i * jNum * kNum + (j + Alt) * kNum + k;
        int idx_kAlt = i * jNum * kNum + j * kNum + (k + Alt);
        
        if (Cx && Cy && Cz) {
            // Full coefficient update
            Fx[idx] += (dtdz[k] * (Gy[idx] - Gy[idx_kAlt]) + 
                       dtdy[j] * (Gz[idx_jAlt] - Gz[idx])) * Cx[idx];
            Fy[idx] += (dtdx[i] * (Gz[idx] - Gz[idx_iAlt]) + 
                       dtdz[k] * (Gx[idx_kAlt] - Gx[idx])) * Cy[idx];
            Fz[idx] += (dtdy[j] * (Gx[idx] - Gx[idx_jAlt]) + 
                       dtdx[i] * (Gy[idx_iAlt] - Gy[idx])) * Cz[idx];
        } else {
            // Simple update without material coefficients
            Fx[idx] += dtdz[k] * (Gy[idx] - Gy[idx_kAlt]) + 
                       dtdy[j] * (Gz[idx_jAlt] - Gz[idx]);
            Fy[idx] += dtdx[i] * (Gz[idx] - Gz[idx_iAlt]) + 
                       dtdz[k] * (Gx[idx_kAlt] - Gx[idx]);
            Fz[idx] += dtdy[j] * (Gx[idx] - Gx[idx_jAlt]) + 
                       dtdx[i] * (Gy[idx_iAlt] - Gy[idx]);
        }
    }
}

// GPU memory management functions
typedef struct {
    float *d_Ex, *d_Ey, *d_Ez;
    float *d_Hx, *d_Hy, *d_Hz;
    float *d_dtdx, *d_dtdy, *d_dtdz;
    float *d_Cx, *d_Cy, *d_Cz;
    size_t field_size;
    int iNum, jNum, kNum;
    bool initialized;
} cuda_fields;

static cuda_fields gpu_fields = {0};

bool cuda_init_fields(world W) {
    if (gpu_fields.initialized) return true;
    
    gpu_fields.iNum = W->iNUM;
    gpu_fields.jNum = W->jNUM;
    gpu_fields.kNum = W->kNUM;
    gpu_fields.field_size = gpu_fields.iNum * gpu_fields.jNum * gpu_fields.kNum * sizeof(float);
    
    // Allocate GPU memory for field arrays
    cudaError_t err;
    err = cudaMalloc(&gpu_fields.d_Ex, gpu_fields.field_size);
    if (err != cudaSuccess) return false;
    err = cudaMalloc(&gpu_fields.d_Ey, gpu_fields.field_size);
    if (err != cudaSuccess) return false;
    err = cudaMalloc(&gpu_fields.d_Ez, gpu_fields.field_size);
    if (err != cudaSuccess) return false;
    err = cudaMalloc(&gpu_fields.d_Hx, gpu_fields.field_size);
    if (err != cudaSuccess) return false;
    err = cudaMalloc(&gpu_fields.d_Hy, gpu_fields.field_size);
    if (err != cudaSuccess) return false;
    err = cudaMalloc(&gpu_fields.d_Hz, gpu_fields.field_size);
    if (err != cudaSuccess) return false;
    
    // Allocate coefficient arrays
    err = cudaMalloc(&gpu_fields.d_dtdx, W->iNUM * sizeof(float));
    if (err != cudaSuccess) return false;
    err = cudaMalloc(&gpu_fields.d_dtdy, W->jNUM * sizeof(float));
    if (err != cudaSuccess) return false;
    err = cudaMalloc(&gpu_fields.d_dtdz, W->kNUM * sizeof(float));
    if (err != cudaSuccess) return false;
    
    // Material coefficients allocated on demand
    gpu_fields.d_Cx = nullptr;
    gpu_fields.d_Cy = nullptr;
    gpu_fields.d_Cz = nullptr;
    
    gpu_fields.initialized = true;
    return true;
}

void cuda_cleanup_fields() {
    if (!gpu_fields.initialized) return;
    
    cudaFree(gpu_fields.d_Ex);
    cudaFree(gpu_fields.d_Ey);
    cudaFree(gpu_fields.d_Ez);
    cudaFree(gpu_fields.d_Hx);
    cudaFree(gpu_fields.d_Hy);
    cudaFree(gpu_fields.d_Hz);
    cudaFree(gpu_fields.d_dtdx);
    cudaFree(gpu_fields.d_dtdy);
    cudaFree(gpu_fields.d_dtdz);
    
    if (gpu_fields.d_Cx) cudaFree(gpu_fields.d_Cx);
    if (gpu_fields.d_Cy) cudaFree(gpu_fields.d_Cy);
    if (gpu_fields.d_Cz) cudaFree(gpu_fields.d_Cz);
    
    memset(&gpu_fields, 0, sizeof(cuda_fields));
}

// Convert 3D field array to 1D for GPU transfer
void copy_field_to_1d(float ***field_3d, float *field_1d, int iMin, int iMax, int jMin, int jMax, int kMin, int kMax, int jNum, int kNum) {
    for (int i = iMin; i <= iMax; i++) {
        for (int j = jMin; j <= jMax; j++) {
            for (int k = kMin; k <= kMax; k++) {
                int idx = i * jNum * kNum + j * kNum + k;
                field_1d[idx] = field_3d[i][j][k];
            }
        }
    }
}

void copy_field_from_1d(float *field_1d, float ***field_3d, int iMin, int iMax, int jMin, int jMax, int kMin, int kMax, int jNum, int kNum) {
    for (int i = iMin; i <= iMax; i++) {
        for (int j = jMin; j <= jMax; j++) {
            for (int k = kMin; k <= kMax; k++) {
                int idx = i * jNum * kNum + j * kNum + k;
                field_3d[i][j][k] = field_1d[idx];
            }
        }
    }
}

extern "C" {

bool cuda_updateF(world W, vfield F, vfield G, coeffs *C, int Alt, int iMin, int iMax, int jMin, int jMax, int kMin, int kMax) {
    if (!cuda_init_fields(W)) return false;
    
    // Allocate temporary host memory for field transfer
    size_t temp_size = gpu_fields.field_size;
    float *temp_F = (float*)malloc(temp_size);
    float *temp_G = (float*)malloc(temp_size);
    if (!temp_F || !temp_G) {
        if (temp_F) free(temp_F);
        if (temp_G) free(temp_G);
        return false;
    }
    
    // Copy fields from CPU to temporary arrays
    copy_field_to_1d(F.x, temp_F, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    cudaMemcpy(gpu_fields.d_Ex, temp_F, temp_size, cudaMemcpyHostToDevice);
    
    copy_field_to_1d(F.y, temp_F, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    cudaMemcpy(gpu_fields.d_Ey, temp_F, temp_size, cudaMemcpyHostToDevice);
    
    copy_field_to_1d(F.z, temp_F, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    cudaMemcpy(gpu_fields.d_Ez, temp_F, temp_size, cudaMemcpyHostToDevice);
    
    copy_field_to_1d(G.x, temp_G, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    cudaMemcpy(gpu_fields.d_Hx, temp_G, temp_size, cudaMemcpyHostToDevice);
    
    copy_field_to_1d(G.y, temp_G, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    cudaMemcpy(gpu_fields.d_Hy, temp_G, temp_size, cudaMemcpyHostToDevice);
    
    copy_field_to_1d(G.z, temp_G, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    cudaMemcpy(gpu_fields.d_Hz, temp_G, temp_size, cudaMemcpyHostToDevice);
    
    // Copy coefficients
    cudaMemcpy(gpu_fields.d_dtdx, C->dtdx, W->iNUM * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(gpu_fields.d_dtdy, C->dtdy, W->jNUM * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(gpu_fields.d_dtdz, C->dtdz, W->kNUM * sizeof(float), cudaMemcpyHostToDevice);
    
    float *d_Cx = nullptr, *d_Cy = nullptr, *d_Cz = nullptr;
    if (C->x && C->y && C->z) {
        // Allocate material coefficient arrays if needed
        if (!gpu_fields.d_Cx) {
            cudaMalloc(&gpu_fields.d_Cx, temp_size);
            cudaMalloc(&gpu_fields.d_Cy, temp_size);
            cudaMalloc(&gpu_fields.d_Cz, temp_size);
        }
        
        copy_field_to_1d(C->x, temp_F, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
        cudaMemcpy(gpu_fields.d_Cx, temp_F, temp_size, cudaMemcpyHostToDevice);
        
        copy_field_to_1d(C->y, temp_F, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
        cudaMemcpy(gpu_fields.d_Cy, temp_F, temp_size, cudaMemcpyHostToDevice);
        
        copy_field_to_1d(C->z, temp_F, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
        cudaMemcpy(gpu_fields.d_Cz, temp_F, temp_size, cudaMemcpyHostToDevice);
        
        d_Cx = gpu_fields.d_Cx;
        d_Cy = gpu_fields.d_Cy;
        d_Cz = gpu_fields.d_Cz;
    }
    
    // Launch CUDA kernel
    dim3 blockSize(8, 8, 8);
    dim3 gridSize(
        (iMax - iMin + blockSize.x) / blockSize.x,
        (jMax - jMin + blockSize.y) / blockSize.y,
        (kMax - kMin + blockSize.z) / blockSize.z
    );
    
    updateF_kernel<<<gridSize, blockSize>>>(
        gpu_fields.d_Ex, gpu_fields.d_Ey, gpu_fields.d_Ez,
        gpu_fields.d_Hx, gpu_fields.d_Hy, gpu_fields.d_Hz,
        d_Cx, d_Cy, d_Cz,
        gpu_fields.d_dtdx, gpu_fields.d_dtdy, gpu_fields.d_dtdz,
        Alt, iMin, iMax, jMin, jMax, kMin, kMax,
        gpu_fields.iNum, gpu_fields.jNum, gpu_fields.kNum
    );
    
    cudaDeviceSynchronize();
    
    // Copy results back to CPU
    cudaMemcpy(temp_F, gpu_fields.d_Ex, temp_size, cudaMemcpyDeviceToHost);
    copy_field_from_1d(temp_F, F.x, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    
    cudaMemcpy(temp_F, gpu_fields.d_Ey, temp_size, cudaMemcpyDeviceToHost);
    copy_field_from_1d(temp_F, F.y, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    
    cudaMemcpy(temp_F, gpu_fields.d_Ez, temp_size, cudaMemcpyDeviceToHost);
    copy_field_from_1d(temp_F, F.z, W->iMIN, W->iMAX, W->jMIN, W->jMAX, W->kMIN, W->kMAX, gpu_fields.jNum, gpu_fields.kNum);
    
    free(temp_F);
    free(temp_G);
    
    return true;
}

} // extern "C"