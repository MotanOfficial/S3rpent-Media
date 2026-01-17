#ifndef SUBTITLEFORMATTER_H
#define SUBTITLEFORMATTER_H

#include <QObject>
#include <QString>

class SubtitleFormatter : public QObject
{
    Q_OBJECT
    
public:
    explicit SubtitleFormatter(QObject *parent = nullptr);
    
    // Parse ASS/SSA formatting codes and convert to HTML
    Q_INVOKABLE QString formatSubtitle(const QString &text) const;
    
private:
    // Helper functions for parsing ASS/SSA codes
    QString parseASSCodes(const QString &text) const;
    QString removeASSTags(const QString &text) const;
    bool isASSTag(const QString &tag) const;
};

#endif // SUBTITLEFORMATTER_H

