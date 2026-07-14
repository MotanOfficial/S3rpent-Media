#include "audiocoverparticlegeometry.h"

#include <cstddef>

#include <QVector3D>
#include <QtMath>

namespace {
constexpr float kPlaneSize = 4.8f;

struct ParticleVertex {
    float x = 0;
    float y = 0;
    float z = 0;
    float cellU = 0;
    float cellV = 0;
    float quadU = 0;
    float quadV = 0;
};

void writeVertex(float *&cursor, const ParticleVertex &vertex)
{
    *cursor++ = vertex.x;
    *cursor++ = vertex.y;
    *cursor++ = vertex.z;
    *cursor++ = vertex.cellU;
    *cursor++ = vertex.cellV;
    *cursor++ = vertex.quadU;
    *cursor++ = vertex.quadV;
}
} // namespace

AudioCoverParticleGeometry::AudioCoverParticleGeometry()
{
    rebuild();
}

void AudioCoverParticleGeometry::setGridResolution(int resolution)
{
    const int clamped = qBound(32, resolution, 80);
    if (m_gridResolution == clamped)
        return;
    m_gridResolution = clamped;
    rebuild();
    emit gridResolutionChanged();
}

void AudioCoverParticleGeometry::rebuild()
{
    const int grid = qBound(32, m_gridResolution, 80);
    const int cellCount = grid * grid;
    const float texelStep = 1.0f / static_cast<float>(grid);
    const float quadHalf = (kPlaneSize / static_cast<float>(grid)) * 0.92f;

    QByteArray vertexData;
    vertexData.resize(cellCount * 6 * static_cast<int>(sizeof(ParticleVertex)));
    float *vertices = reinterpret_cast<float *>(vertexData.data());

    static constexpr float kQuadUv[4][2] = {
        { 0.0f, 0.0f },
        { 1.0f, 0.0f },
        { 1.0f, 1.0f },
        { 0.0f, 1.0f },
    };

    for (int i = 0; i < cellCount; ++i) {
        const int gx = i % grid;
        const int gy = i / grid;
        const float cellU = (static_cast<float>(gx) + 0.5f) * texelStep;
        const float cellV = (static_cast<float>(gy) + 0.5f) * texelStep;
        const float px = static_cast<float>(gx) / static_cast<float>(grid - 1);
        const float py = static_cast<float>(gy) / static_cast<float>(grid - 1);
        const float cx = (px - 0.5f) * kPlaneSize;
        const float cy = (py - 0.5f) * kPlaneSize;

        const ParticleVertex corners[4] = {
            { cx - quadHalf, cy - quadHalf, 0.0f, cellU, cellV, kQuadUv[0][0], kQuadUv[0][1] },
            { cx + quadHalf, cy - quadHalf, 0.0f, cellU, cellV, kQuadUv[1][0], kQuadUv[1][1] },
            { cx + quadHalf, cy + quadHalf, 0.0f, cellU, cellV, kQuadUv[2][0], kQuadUv[2][1] },
            { cx - quadHalf, cy + quadHalf, 0.0f, cellU, cellV, kQuadUv[3][0], kQuadUv[3][1] },
        };

        const int indices[6] = { 0, 1, 2, 0, 2, 3 };
        for (int tri = 0; tri < 6; ++tri)
            writeVertex(vertices, corners[indices[tri]]);
    }

    setStride(static_cast<int>(sizeof(ParticleVertex)));
    setVertexData(vertexData);
    setPrimitiveType(QQuick3DGeometry::PrimitiveType::Triangles);
    setBounds(QVector3D(-kPlaneSize, -kPlaneSize, -8.0f),
              QVector3D(kPlaneSize, kPlaneSize, 8.0f));

    clear();
    addAttribute(QQuick3DGeometry::Attribute::PositionSemantic,
                 0,
                 QQuick3DGeometry::Attribute::F32Type);
    addAttribute(QQuick3DGeometry::Attribute::TexCoordSemantic,
                 offsetof(ParticleVertex, cellU),
                 QQuick3DGeometry::Attribute::F32Type);
    addAttribute(QQuick3DGeometry::Attribute::TexCoord1Semantic,
                 offsetof(ParticleVertex, quadU),
                 QQuick3DGeometry::Attribute::F32Type);

    update();
}
