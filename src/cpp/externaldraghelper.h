#pragma once

#include <QObject>
#include <QUrl>

class ExternalDragHelper : public QObject
{
    Q_OBJECT
public:
    explicit ExternalDragHelper(QObject *parent = nullptr);

    Q_INVOKABLE bool startFileDrag(const QUrl &fileUrl, const QString &label = QString());
};

