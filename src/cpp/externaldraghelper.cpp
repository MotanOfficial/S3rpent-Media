#include "externaldraghelper.h"

#include <QDrag>
#include <QMimeData>
#include <QFileInfo>
#include <QPainter>
#include <QFont>
#include <QFontMetrics>
#include <QPixmap>

ExternalDragHelper::ExternalDragHelper(QObject *parent)
    : QObject(parent)
{
}

bool ExternalDragHelper::startFileDrag(const QUrl &fileUrl, const QString &label)
{
    if (!fileUrl.isValid() || !fileUrl.isLocalFile()) {
        return false;
    }

    const QString localPath = fileUrl.toLocalFile();
    if (!QFileInfo::exists(localPath)) {
        return false;
    }

    auto *mime = new QMimeData();
    mime->setUrls({QUrl::fromLocalFile(localPath)});

    auto *drag = new QDrag(this);
    drag->setMimeData(mime);

    // Create a readable drag badge so user sees what is being dragged.
    const QString display = label.isEmpty() ? QFileInfo(localPath).fileName() : label;
    QFont font;
    font.setPointSize(10);
    font.setBold(true);
    QFontMetrics fm(font);
    const int textW = qMin(360, fm.horizontalAdvance(display));
    const int w = textW + 34;
    const int h = 28;
    QPixmap pm(w, h);
    pm.fill(Qt::transparent);
    {
        QPainter p(&pm);
        p.setRenderHint(QPainter::Antialiasing, true);
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(20, 20, 24, 235));
        p.drawRoundedRect(QRectF(0, 0, w - 1, h - 1), 8, 8);

        // Small white square icon.
        p.setBrush(QColor(245, 245, 245));
        p.drawRoundedRect(QRectF(8, 8, 10, 10), 2, 2);

        p.setPen(QColor(245, 245, 245));
        p.setFont(font);
        p.drawText(QRect(24, 0, w - 28, h), Qt::AlignVCenter | Qt::AlignLeft,
                   fm.elidedText(display, Qt::ElideRight, w - 32));
    }
    drag->setPixmap(pm);
    drag->setHotSpot(QPoint(14, 14));

    const Qt::DropAction action = drag->exec(Qt::CopyAction);
    return action == Qt::CopyAction;
}

