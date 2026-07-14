#include "audiostarfieldgeometry.h"

#include <cstddef>

#include <QRandomGenerator>
#include <QVector3D>
#include <QtMath>

namespace {
constexpr float kStarHalf = 0.16f;

struct StarVertex {
    float x = 0;
    float y = 0;
    float z = 0;
    float u = 0;
    float v = 0;
};

void writeVertex(float *&cursor, const StarVertex &vertex)
{
    *cursor++ = vertex.x;
    *cursor++ = vertex.y;
    *cursor++ = vertex.z;
    *cursor++ = vertex.u;
    *cursor++ = vertex.v;
}
} // namespace

AudioStarfieldGeometry::AudioStarfieldGeometry()
{
    rebuild();
}

void AudioStarfieldGeometry::setStarCount(int count)
{
    const int clamped = qBound(400, count, 3000);
    if (m_starCount == clamped)
        return;
    m_starCount = clamped;
    rebuild();
    emit starCountChanged();
}

void AudioStarfieldGeometry::rebuild()
{
    const int stars = qBound(400, m_starCount, 3000);
    QByteArray vertexData;
    vertexData.resize(stars * 6 * static_cast<int>(sizeof(StarVertex)));
    float *vertices = reinterpret_cast<float *>(vertexData.data());

    float maxR = 0.0f;
    for (int i = 0; i < stars; ++i) {
        const float u = static_cast<float>(QRandomGenerator::global()->generateDouble());
        const float v = static_cast<float>(QRandomGenerator::global()->generateDouble());
        const float w = static_cast<float>(QRandomGenerator::global()->generateDouble());
        const float theta = u * 2.0f * float(M_PI);
        const float phi = std::acos(2.0f * v - 1.0f);
        const float radius = 18.0f + w * 16.0f;
        const float cx = radius * std::sin(phi) * std::cos(theta);
        const float cy = radius * std::sin(phi) * std::sin(theta);
        const float cz = radius * std::cos(phi);
        maxR = std::max(maxR, radius);

        const StarVertex corners[4] = {
            { cx - kStarHalf, cy - kStarHalf, cz, 0.0f, 0.0f },
            { cx + kStarHalf, cy - kStarHalf, cz, 1.0f, 0.0f },
            { cx + kStarHalf, cy + kStarHalf, cz, 1.0f, 1.0f },
            { cx - kStarHalf, cy + kStarHalf, cz, 0.0f, 1.0f },
        };

        const int indices[6] = { 0, 1, 2, 0, 2, 3 };
        for (int tri = 0; tri < 6; ++tri)
            writeVertex(vertices, corners[indices[tri]]);
    }

    setStride(static_cast<int>(sizeof(StarVertex)));
    setVertexData(vertexData);
    setPrimitiveType(QQuick3DGeometry::PrimitiveType::Triangles);
    setBounds(QVector3D(-maxR, -maxR, -maxR), QVector3D(maxR, maxR, maxR));

    clear();
    addAttribute(QQuick3DGeometry::Attribute::PositionSemantic,
                 0,
                 QQuick3DGeometry::Attribute::F32Type);
    addAttribute(QQuick3DGeometry::Attribute::TexCoordSemantic,
                 offsetof(StarVertex, u),
                 QQuick3DGeometry::Attribute::F32Type);

    update();
}
