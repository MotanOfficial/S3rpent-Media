#ifndef AUDIOCOVERPARTICLEGEOMETRY_H
#define AUDIOCOVERPARTICLEGEOMETRY_H

#include <QQuick3DGeometry>

class AudioCoverParticleGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(int gridResolution READ gridResolution WRITE setGridResolution NOTIFY gridResolutionChanged)

public:
    explicit AudioCoverParticleGeometry();

    int gridResolution() const { return m_gridResolution; }
    void setGridResolution(int resolution);

signals:
    void gridResolutionChanged();

private:
    void rebuild();
    int m_gridResolution = 64;
};

#endif // AUDIOCOVERPARTICLEGEOMETRY_H
