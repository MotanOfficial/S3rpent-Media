#ifndef AUDIOSTARFIELDGEOMETRY_H
#define AUDIOSTARFIELDGEOMETRY_H

#include <QQuick3DGeometry>

class AudioStarfieldGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(int starCount READ starCount WRITE setStarCount NOTIFY starCountChanged)

public:
    explicit AudioStarfieldGeometry();

    int starCount() const { return m_starCount; }
    void setStarCount(int count);

signals:
    void starCountChanged();

private:
    void rebuild();
    int m_starCount = 1600;
};

#endif // AUDIOSTARFIELDGEOMETRY_H
