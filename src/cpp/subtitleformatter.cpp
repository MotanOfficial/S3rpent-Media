#include "subtitleformatter.h"
#include <QRegularExpression>
#include <QDebug>

SubtitleFormatter::SubtitleFormatter(QObject *parent)
    : QObject(parent)
{
}

QString SubtitleFormatter::formatSubtitle(const QString &text) const
{
    if (text.isEmpty()) {
        return "";
    }
    
    // Parse ASS/SSA formatting codes and convert to HTML
    return parseASSCodes(text);
}

QString SubtitleFormatter::parseASSCodes(const QString &text) const
{
    QString result = text;
    
    // Stack to track formatting states
    struct FormatState {
        bool bold = false;
        bool italic = false;
        bool underline = false;
        bool strikeout = false;
    };
    
    // Replace ASS/SSA formatting codes with HTML
    // Pattern: {\tag} or {\tag1} or {\tag0}
    // Common tags:
    // \i1 = italic on, \i0 = italic off
    // \b1 = bold on, \b0 = bold off
    // \u1 = underline on, \u0 = underline off
    // \s1 = strikeout on, \s0 = strikeout off
    // \li1 = line spacing (not directly translatable to HTML, but we can handle it)
    
    // First, handle nested tags by processing from innermost to outermost
    // We'll use a simpler approach: replace tags sequentially
    
    // Remove ASS/SSA tag braces and convert to HTML
    // Pattern: {\tag} or {\tag1} or {\tag0} or {\tag value}
    
    // Step 1: Handle italic tags {\i1} and {\i0}
    QRegularExpression italicOnRegex(R"(\{\\i1\})");
    QRegularExpression italicOffRegex(R"(\{\\i0\})");
    result.replace(italicOnRegex, "<i>");
    result.replace(italicOffRegex, "</i>");
    
    // Step 2: Handle bold tags {\b1} and {\b0}
    QRegularExpression boldOnRegex(R"(\{\\b1\})");
    QRegularExpression boldOffRegex(R"(\{\\b0\})");
    result.replace(boldOnRegex, "<b>");
    result.replace(boldOffRegex, "</b>");
    
    // Step 3: Handle underline tags {\u1} and {\u0}
    QRegularExpression underlineOnRegex(R"(\{\\u1\})");
    QRegularExpression underlineOffRegex(R"(\{\\u0\})");
    result.replace(underlineOnRegex, "<u>");
    result.replace(underlineOffRegex, "</u>");
    
    // Step 4: Handle strikeout tags {\s1} and {\s0}
    QRegularExpression strikeoutOnRegex(R"(\{\\s1\})");
    QRegularExpression strikeoutOffRegex(R"(\{\\s0\})");
    result.replace(strikeoutOnRegex, "<s>");
    result.replace(strikeoutOffRegex, "</s>");
    
    // Step 5: Handle tags without explicit 1/0 (assume 1 means on, anything else means off)
    // {\i} = italic on, {\i0} = italic off (already handled above)
    QRegularExpression italicTagRegex(R"(\{\\i\})");
    result.replace(italicTagRegex, "<i>");
    
    QRegularExpression boldTagRegex(R"(\{\\b\})");
    result.replace(boldTagRegex, "<b>");
    
    QRegularExpression underlineTagRegex(R"(\{\\u\})");
    result.replace(underlineTagRegex, "<u>");
    
    // Step 6: Handle tags with values like {\li1} (line spacing) - we'll just remove these
    // as they don't directly map to HTML
    
    // Step 7: Remove remaining ASS tags that we don't handle
    // Pattern: {tag} where tag starts with \ and may have numbers/letters
    // Remove tags like {\li1}, {\an8}, {\pos}, etc. but preserve our HTML tags
    // We need to be careful - remove ASS tags but keep HTML
    QRegularExpression remainingAssTagsRegex(R"(\{[\\][^}]*\})");
    result.replace(remainingAssTagsRegex, "");
    
    // Step 7: Clean up any orphaned tags (opening without closing, etc.)
    // Count opening and closing tags to ensure proper nesting
    int italicOpen = result.count("<i>");
    int italicClose = result.count("</i>");
    int boldOpen = result.count("<b>");
    int boldClose = result.count("</b>");
    int underlineOpen = result.count("<u>");
    int underlineClose = result.count("</u>");
    int strikeoutOpen = result.count("<s>");
    int strikeoutClose = result.count("</s>");
    
    // Add missing closing tags at the end
    if (italicOpen > italicClose) {
        result += QString("</i>").repeated(italicOpen - italicClose);
    }
    if (boldOpen > boldClose) {
        result += QString("</b>").repeated(boldOpen - boldClose);
    }
    if (underlineOpen > underlineClose) {
        result += QString("</u>").repeated(underlineOpen - underlineClose);
    }
    if (strikeoutOpen > strikeoutClose) {
        result += QString("</s>").repeated(strikeoutOpen - strikeoutClose);
    }
    
    // Remove any orphaned closing tags at the beginning
    while (result.startsWith("</")) {
        int endTag = result.indexOf(">");
        if (endTag != -1) {
            result.remove(0, endTag + 1);
        } else {
            break;
        }
    }
    
    return result;
}

QString SubtitleFormatter::removeASSTags(const QString &text) const
{
    // Remove all ASS/SSA tags
    QRegularExpression tagRegex(R"(\{[^}]*\})");
    QString result = text;  // Make a non-const copy
    return result.replace(tagRegex, "");
}

bool SubtitleFormatter::isASSTag(const QString &tag) const
{
    // Check if a string is an ASS/SSA tag
    return tag.startsWith("{") && tag.endsWith("}") && tag.contains("\\");
}

