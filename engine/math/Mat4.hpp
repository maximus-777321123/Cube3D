// Mat4.hpp — матрица 4x4 (column-major, как в OpenGL/Vulkan), GLM-совместимая
#pragma once
#include "Vec3.hpp"

struct Mat4 {
    // m[col][row]
    float m[4][4] = {};

    static Mat4 Identity() {
        Mat4 r;
        r.m[0][0] = r.m[1][1] = r.m[2][2] = r.m[3][3] = 1.f;
        return r;
    }

    static Mat4 Translate(const Vec3& t) {
        Mat4 r = Identity();
        r.m[3][0] = t.x; r.m[3][1] = t.y; r.m[3][2] = t.z;
        return r;
    }

    static Mat4 Scale(const Vec3& s) {
        Mat4 r;
        r.m[0][0] = s.x; r.m[1][1] = s.y; r.m[2][2] = s.z; r.m[3][3] = 1.f;
        return r;
    }

    static Mat4 RotateY(float angleRad) {
        Mat4 r = Identity();
        float c = std::cos(angleRad), s = std::sin(angleRad);
        r.m[0][0] =  c; r.m[0][2] = -s;
        r.m[2][0] =  s; r.m[2][2] =  c;
        return r;
    }

    static Mat4 Perspective(float fovYRad, float aspect, float znear, float zfar) {
        Mat4 r;
        float f = 1.f / std::tan(fovYRad * 0.5f);
        r.m[0][0] = f / aspect;
        r.m[1][1] = f;
        r.m[2][2] = (zfar + znear) / (znear - zfar);
        r.m[2][3] = -1.f;
        r.m[3][2] = (2.f * zfar * znear) / (znear - zfar);
        return r;
    }

    static Mat4 LookAt(const Vec3& eye, const Vec3& center, const Vec3& up) {
        Vec3 f = (center - eye).Normalized();
        Vec3 s = f.Cross(up).Normalized();
        Vec3 u = s.Cross(f);
        Mat4 r = Identity();
        r.m[0][0] = s.x; r.m[1][0] = s.y; r.m[2][0] = s.z;
        r.m[0][1] = u.x; r.m[1][1] = u.y; r.m[2][1] = u.z;
        r.m[0][2] = -f.x; r.m[1][2] = -f.y; r.m[2][2] = -f.z;
        r.m[3][0] = -s.Dot(eye);
        r.m[3][1] = -u.Dot(eye);
        r.m[3][2] =  f.Dot(eye);
        return r;
    }

    Mat4 operator*(const Mat4& b) const {
        Mat4 r;
        for (int c = 0; c < 4; ++c)
            for (int row = 0; row < 4; ++row) {
                float acc = 0.f;
                for (int k = 0; k < 4; ++k) acc += m[k][row] * b.m[c][k];
                r.m[c][row] = acc;
            }
        return r;
    }
};
