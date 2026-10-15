// Vec3.hpp — 3D-вектор и базовая линейная алгебра движка (C++17, без внешних зависимостей)
#pragma once
#include <cmath>

struct Vec2 {
    float x = 0.f, y = 0.f;
};

struct Vec3 {
    float x = 0.f, y = 0.f, z = 0.f;

    Vec3() = default;
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}

    Vec3 operator+(const Vec3& o) const { return {x + o.x, y + o.y, z + o.z}; }
    Vec3 operator-(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
    Vec3 operator*(float s)       const { return {x * s, y * s, z * s}; }

    float Dot(const Vec3& o) const { return x * o.x + y * o.y + z * o.z; }

    Vec3 Cross(const Vec3& o) const {
        return {y * o.z - z * o.y,
                z * o.x - x * o.z,
                x * o.y - y * o.x};
    }

    float Length() const { return std::sqrt(Dot(*this)); }

    Vec3 Normalized() const {
        float l = Length();
        return l > 1e-8f ? (*this) * (1.f / l) : Vec3{};
    }
};

inline Vec3 operator*(float s, const Vec3& v) { return v * s; }
