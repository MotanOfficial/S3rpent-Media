#include "modelsourceresolver.h"

#include <QtConcurrent>

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QTextStream>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace {
constexpr auto kBlendExportCacheVersion = "blend_export_v9";

bool normalizeObjMtlTexturePaths(const QString &objPath)
{
    const QString mtlPath = QFileInfo(objPath).absolutePath() + "/" + QFileInfo(objPath).completeBaseName() + ".mtl";
    QFileInfo mtlInfo(mtlPath);
    if (!mtlInfo.exists())
        return true;

    const QDir dir = mtlInfo.dir();
    const QStringList files = dir.entryList(QDir::Files | QDir::Readable);
    QHash<QString, QString> byBase;
    QHash<QString, QString> byStem;
    for (const QString &f : files) {
        const QString lowerBase = f.toLower();
        const QString lowerStem = QFileInfo(f).completeBaseName().toLower();
        if (!byBase.contains(lowerBase))
            byBase.insert(lowerBase, f);
        if (!byStem.contains(lowerStem))
            byStem.insert(lowerStem, f);
    }

    QFile in(mtlPath);
    if (!in.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    QStringList outLines;
    QTextStream reader(&in);
    while (!reader.atEnd()) {
        const QString line = reader.readLine();
        const QString trimmed = line.trimmed();
        if (trimmed.isEmpty() || trimmed.startsWith('#')) {
            outLines << line;
            continue;
        }

        const int firstSpace = trimmed.indexOf(' ');
        if (firstSpace <= 0) {
            outLines << line;
            continue;
        }

        const QString cmd = trimmed.left(firstSpace);
        const QString lowerCmd = cmd.toLower();
        if (!(lowerCmd.startsWith("map_") || lowerCmd == "bump" || lowerCmd == "disp" || lowerCmd == "decal" || lowerCmd == "refl")) {
            outLines << line;
            continue;
        }

        const QString rhs = trimmed.mid(firstSpace + 1).trimmed();
        QString base = QFileInfo(rhs).fileName();
        if (base.isEmpty()) {
            // Fallback for weird rhs formats.
            const int slashPos = qMax(rhs.lastIndexOf('/'), rhs.lastIndexOf('\\'));
            base = slashPos >= 0 ? rhs.mid(slashPos + 1) : rhs;
            base = base.trimmed();
        }
        if (base.isEmpty())
            continue; // Drop unresolved map line.

        const QString stem = QFileInfo(base).completeBaseName();
        const QString ext = QFileInfo(base).suffix().toLower();
        QString chosen;

        // Prefer PNG replacement for TGA when available.
        if (ext == "tga") {
            const QString pngBase = stem + ".png";
            if (byBase.contains(pngBase.toLower()))
                chosen = byBase.value(pngBase.toLower());
        }
        if (chosen.isEmpty() && byBase.contains(base.toLower()))
            chosen = byBase.value(base.toLower());
        if (chosen.isEmpty() && byStem.contains(stem.toLower()))
            chosen = byStem.value(stem.toLower());

        if (chosen.isEmpty())
            continue; // Drop unresolved map line to avoid hard-fail lookups.

        outLines << (cmd + " " + chosen);
    }
    in.close();

    QFile out(mtlPath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate))
        return false;
    QTextStream writer(&out);
    for (const QString &l : outLines)
        writer << l << '\n';
    return true;
}
} // namespace

ModelSourceResolver::ModelSourceResolver(QObject *parent)
    : QObject(parent)
{
}

QString ModelSourceResolver::lastError() const
{
    return m_lastError;
}

bool ModelSourceResolver::resolving() const
{
    return m_resolving;
}

void ModelSourceResolver::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void ModelSourceResolver::setResolving(bool value)
{
    if (m_resolving == value)
        return;
    m_resolving = value;
    emit resolvingChanged();
}

QString ModelSourceResolver::extensionLower(const QString &filePath)
{
    return QFileInfo(filePath).suffix().toLower();
}

QUrl ModelSourceResolver::resolveForViewing(const QUrl &sourceUrl)
{
    QString error;
    const QUrl resolved = resolveForViewingInternal(sourceUrl, &error);
    setLastError(error);
    return resolved;
}

void ModelSourceResolver::resolveForViewingAsync(const QUrl &sourceUrl)
{
    resolveForViewingAsync(sourceUrl, QVariantMap());
}

void ModelSourceResolver::resolveForViewingAsync(const QUrl &sourceUrl, const QVariantMap &propertyOverrides)
{
    const quint64 token = ++m_requestToken;
    setResolving(true);

    auto *watcher = new QFutureWatcher<QPair<QUrl, QString>>(this);
    connect(watcher, &QFutureWatcher<QPair<QUrl, QString>>::finished, this, [this, watcher, token, sourceUrl]() {
        const QPair<QUrl, QString> result = watcher->result();
        watcher->deleteLater();

        // Ignore stale completion from older requests.
        if (token != m_requestToken)
            return;

        setLastError(result.second);
        setResolving(false);
        emit resolveFinished(sourceUrl, result.first, result.second);
    });

    const QVariantMap overrides = propertyOverrides;
    watcher->setFuture(QtConcurrent::run([sourceUrl, overrides]() -> QPair<QUrl, QString> {
        QString error;
        const QUrl resolved = ModelSourceResolver::resolveForViewingInternal(sourceUrl, &error, overrides);
        return qMakePair(resolved, error);
    }));
}

QUrl ModelSourceResolver::resolveForViewingInternal(const QUrl &sourceUrl, QString *errorOut, const QVariantMap &propertyOverrides)
{
    if (errorOut)
        *errorOut = QString();
    if (!sourceUrl.isLocalFile())
        return sourceUrl;

    const QString sourcePath = sourceUrl.toLocalFile();
    if (sourcePath.isEmpty())
        return sourceUrl;

    const QString ext = extensionLower(sourcePath);
    if (ext == "mtl") {
        const QString objPath = findObjForMtl(sourcePath);
        if (objPath.isEmpty()) {
            if (errorOut)
                *errorOut = tr("No matching OBJ found for this MTL file.");
            return QUrl();
        }
        return QUrl::fromLocalFile(objPath);
    }

    if (ext == "blend") {
        QString convertError;
        const QString glbPath = convertBlendToGlb(sourcePath, &convertError, propertyOverrides);
        if (glbPath.isEmpty())
        {
            if (errorOut)
                *errorOut = convertError;
            return QUrl();
        }
        return QUrl::fromLocalFile(glbPath);
    }

    return sourceUrl;
}

QString ModelSourceResolver::findObjForMtl(const QString &mtlPath)
{
    const QFileInfo mtlInfo(mtlPath);
    const QDir dir = mtlInfo.dir();
    const QString mtlFileName = mtlInfo.fileName();

    const QString sameBaseObj = dir.absoluteFilePath(mtlInfo.completeBaseName() + ".obj");
    if (QFileInfo::exists(sameBaseObj))
        return sameBaseObj;

    const QStringList objFiles = dir.entryList(QStringList() << "*.obj", QDir::Files | QDir::Readable);
    for (const QString &objName : objFiles) {
        QFile objFile(dir.absoluteFilePath(objName));
        if (!objFile.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        QTextStream stream(&objFile);
        int scannedLines = 0;
        while (!stream.atEnd() && scannedLines < 2000) {
            const QString line = stream.readLine().trimmed();
            ++scannedLines;
            if (line.startsWith("mtllib ", Qt::CaseInsensitive)) {
                const QString refName = line.mid(7).trimmed();
                if (refName.compare(mtlFileName, Qt::CaseInsensitive) == 0)
                    return dir.absoluteFilePath(objName);
            }
        }
    }

    return QString();
}

QString ModelSourceResolver::findBlenderExecutable()
{
    const QString fromEnv = qEnvironmentVariable("BLENDER_EXECUTABLE");
    if (!fromEnv.isEmpty() && QFileInfo::exists(fromEnv))
        return fromEnv;

    const QString fromPath = QStandardPaths::findExecutable("blender");
    if (!fromPath.isEmpty())
        return fromPath;

#ifdef Q_OS_WIN
    const QStringList baseDirs = {
        QStringLiteral("C:/Program Files/Blender Foundation"),
        QStringLiteral("C:/Program Files (x86)/Blender Foundation")
    };

    for (const QString &base : baseDirs) {
        QDir root(base);
        if (!root.exists())
            continue;
        const QStringList subdirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed);
        for (const QString &sub : subdirs) {
            const QString candidate = root.absoluteFilePath(sub + "/blender.exe");
            if (QFileInfo::exists(candidate))
                return candidate;
        }
    }
#endif
    return QString();
}

QString ModelSourceResolver::ensureCacheDir()
{
    const QString tempRoot = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    QDir cacheDir(tempRoot + "/s3rpent_media_model_cache");
    if (!cacheDir.exists()) {
        cacheDir.mkpath(".");
    }
    return cacheDir.absolutePath();
}

QString ModelSourceResolver::cachePathForBlend(const QString &blendPath, const QVariantMap &propertyOverrides)
{
    const QFileInfo info(blendPath);
    const QString cacheKey = blendPath + "|" + info.lastModified().toString(Qt::ISODateWithMs) + "|" + QString::fromLatin1(kBlendExportCacheVersion);
    const QByteArray hashBytes = QCryptographicHash::hash(cacheKey.toUtf8(), QCryptographicHash::Sha1).toHex();
    const QString hash = QString::fromUtf8(hashBytes.left(10));
    QString safeBase = info.completeBaseName();
    // Quick3D internal mesh references use "!N@<path>" format; keep cache names free of '@'
    // and other special characters to avoid parser issues.
    safeBase.replace(QRegularExpression("[^A-Za-z0-9_-]"), "_");
    safeBase.replace(QRegularExpression("_+"), "_");
    safeBase = safeBase.trimmed();
    if (safeBase.isEmpty())
        safeBase = "blend_model";
    if (safeBase.length() > 64)
        safeBase = safeBase.left(64);
    QString fileName = safeBase + "_" + hash;
    if (!propertyOverrides.isEmpty()) {
        const QByteArray optsJson = QJsonDocument(QJsonObject::fromVariantMap(propertyOverrides)).toJson(QJsonDocument::Compact);
        const QString optsHash = QString::fromUtf8(QCryptographicHash::hash(optsJson, QCryptographicHash::Sha1).toHex().left(8));
        fileName += "_opts_" + optsHash;
    }
    fileName += ".glb";
    return QDir(ensureCacheDir()).absoluteFilePath(fileName);
}

QString ModelSourceResolver::propsPathForBlend(const QString &blendPath)
{
    const QString glbPath = cachePathForBlend(blendPath, QVariantMap());
    const QFileInfo fi(glbPath);
    return fi.absolutePath() + QLatin1Char('/') + fi.completeBaseName() + QLatin1String("_props.json");
}

QString ModelSourceResolver::visibilityMapPathForBlend(const QString &blendPath)
{
    const QString glbPath = cachePathForBlend(blendPath, QVariantMap());
    const QFileInfo fi(glbPath);
    return fi.absolutePath() + QLatin1Char('/') + fi.completeBaseName() + QLatin1String("_visibility.json");
}

QString ModelSourceResolver::matMapPathForBlend(const QString &blendPath)
{
    const QString glbPath = cachePathForBlend(blendPath, QVariantMap());
    const QFileInfo fi(glbPath);
    return fi.absolutePath() + QLatin1Char('/') + fi.completeBaseName() + QLatin1String("_matmap.json");
}

QString ModelSourceResolver::partsJsonPathForBlend(const QString &blendPath)
{
    const QString glbPath = cachePathForBlend(blendPath, QVariantMap());
    const QFileInfo fi(glbPath);
    return fi.absolutePath() + QLatin1Char('/') + fi.completeBaseName() + QLatin1String("_parts.json");
}

QVariantMap ModelSourceResolver::getResolvedModelParts(const QUrl &blendUrl) const
{
    const QString path = blendUrl.toLocalFile();
    if (path.isEmpty())
        return QVariantMap();
    const QString partsPath = partsJsonPathForBlend(path);
    QFile f(partsPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QVariantMap();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return QVariantMap();
    const QJsonObject root = doc.object();
    const QString baseFn = root.value(QLatin1String("base")).toString();
    const QJsonObject partsObj = root.value(QLatin1String("parts")).toObject();
    if (baseFn.isEmpty() || partsObj.isEmpty())
        return QVariantMap();
    const QDir dir = QFileInfo(partsPath).absolutePath();
    QVariantMap result;
    result.insert(QLatin1String("base"), QUrl::fromLocalFile(dir.absoluteFilePath(baseFn)));
    QVariantMap parts;
    for (auto it = partsObj.begin(); it != partsObj.end(); ++it) {
        const QString fn = it.value().toString();
        if (!fn.isEmpty())
            parts.insert(it.key(), QUrl::fromLocalFile(dir.absoluteFilePath(fn)));
    }
    result.insert(QLatin1String("parts"), parts);
    const QJsonArray baseNames = root.value(QLatin1String("baseMeshNames")).toArray();
    QVariantList baseMeshNames;
    for (const QJsonValue &v : baseNames) {
        if (v.isString())
            baseMeshNames.append(v.toString());
    }
    result.insert(QLatin1String("baseMeshNames"), baseMeshNames);
    const QJsonArray bodyNames = root.value(QLatin1String("bodyMeshNames")).toArray();
    QVariantList bodyMeshNames;
    for (const QJsonValue &v : bodyNames) {
        if (v.isString())
            bodyMeshNames.append(v.toString());
    }
    result.insert(QLatin1String("bodyMeshNames"), bodyMeshNames);
    const QString skinMeshFn = root.value(QLatin1String("skinMesh")).toString();
    if (!skinMeshFn.isEmpty())
        result.insert(QLatin1String("skinMesh"), QUrl::fromLocalFile(dir.absoluteFilePath(skinMeshFn)));
    const QString stem = baseFn.left(baseFn.indexOf(QLatin1String("_base")));
    if (!stem.isEmpty()) {
        const QString customPath = dir.absoluteFilePath(stem + QLatin1String("_custom_materials.json"));
        QFile cf(customPath);
        if (cf.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QJsonParseError cerr;
            const QJsonDocument cdoc = QJsonDocument::fromJson(cf.readAll(), &cerr);
            cf.close();
            if (cerr.error == QJsonParseError::NoError && cdoc.isObject())
                result.insert(QLatin1String("customMaterials"), cdoc.object().toVariantMap());
        }
    }
    return result;
}

QVariantList ModelSourceResolver::getDiscoveredBlendProperties(const QUrl &blendUrl) const
{
    const QString path = blendUrl.toLocalFile();
    if (path.isEmpty())
        return QVariantList();
    const QString propsPath = propsPathForBlend(path);
    QFile f(propsPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QVariantList();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();
    if (err.error != QJsonParseError::NoError || !doc.isArray())
        return QVariantList();
    QVariantList list;
    for (const QJsonValue &v : doc.array()) {
        if (!v.isObject())
            continue;
        const QJsonObject o = v.toObject();
        QVariantMap m;
        m.insert(QLatin1String("name"), o.value(QLatin1String("name")).toVariant());
        m.insert(QLatin1String("label"), o.value(QLatin1String("label")).toVariant());
        m.insert(QLatin1String("type"), o.value(QLatin1String("type")).toVariant());
        m.insert(QLatin1String("defaultVal"), o.value(QLatin1String("defaultVal")).toVariant());
        m.insert(QLatin1String("minVal"), o.value(QLatin1String("minVal")).toVariant());
        m.insert(QLatin1String("maxVal"), o.value(QLatin1String("maxVal")).toVariant());
        list.append(m);
    }
    return list;
}

QVariantMap ModelSourceResolver::getBlendVisibilityMap(const QUrl &blendUrl) const
{
    const QString path = blendUrl.toLocalFile();
    if (path.isEmpty())
        return QVariantMap();
    const QString mapPath = visibilityMapPathForBlend(path);
    QFile f(mapPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QVariantMap();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return QVariantMap();
    return doc.object().toVariantMap();
}

QVariantMap ModelSourceResolver::getBlendMaterialMap(const QUrl &blendUrl) const
{
    const QString path = blendUrl.toLocalFile();
    if (path.isEmpty())
        return QVariantMap();
    const QString mapPath = matMapPathForBlend(path);
    QFile f(mapPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QVariantMap();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return QVariantMap();
    return doc.object().toVariantMap();
}

QString ModelSourceResolver::convertBlendToGlb(const QString &blendPath, QString *errorOut, const QVariantMap &propertyOverrides)
{
    qInfo() << "[ModelSourceResolver] Starting .blend conversion:" << blendPath;
    const QString blenderExe = findBlenderExecutable();
    if (blenderExe.isEmpty()) {
        if (errorOut)
            *errorOut = tr("Blender executable not found. Install Blender or set BLENDER_EXECUTABLE.");
        qWarning() << "[ModelSourceResolver] Blender executable not found.";
        return QString();
    }

    const QString outPath = cachePathForBlend(blendPath, propertyOverrides);
    const QString outObjPath = QFileInfo(outPath).absolutePath() + "/" + QFileInfo(outPath).completeBaseName() + ".obj";
    const QString outMtlPath = QFileInfo(outObjPath).absolutePath() + "/" + QFileInfo(outObjPath).completeBaseName() + ".mtl";

    // Never use cache: always run a fresh Blender conversion so exports reflect current pipeline (textures, no animations).
    // Remove existing cached GLB and OBJ/MTL so conversion is always fresh.
    if (QFile::exists(outPath)) {
        QFile::remove(outPath);
        qInfo() << "[ModelSourceResolver] Removed cached GLB for fresh conversion:" << outPath;
    }
    if (QFile::exists(outObjPath))
        QFile::remove(outObjPath);
    if (QFile::exists(outMtlPath))
        QFile::remove(outMtlPath);

    QDir().mkpath(QFileInfo(outPath).absolutePath());

    QTemporaryFile scriptFile(QDir(ensureCacheDir()).absoluteFilePath("blend_export_XXXXXX.py"));
    scriptFile.setAutoRemove(true);
    if (!scriptFile.open()) {
        if (errorOut)
            *errorOut = tr("Failed to create temporary Blender export script.");
        return QString();
    }

    const QByteArray script = QByteArrayLiteral(
        "import bpy\n"
        "import os\n"
        "import re\n"
        "import shutil\n"
        "import sys\n"
        "\n"
        "argv = sys.argv\n"
        "if '--' in argv:\n"
        "    argv = argv[argv.index('--') + 1:]\n"
        "if len(argv) < 3:\n"
        "    raise RuntimeError('Missing export arguments')\n"
        "blend_path, out_glb, out_obj = argv[0], argv[1], argv[2]\n"
        "overrides_path = argv[3] if len(argv) >= 4 and argv[3] else None\n"
        "props_output_path = argv[4] if len(argv) >= 5 and argv[4] else None\n"
        "visibility_map_path = argv[5] if len(argv) >= 6 and argv[5] else None\n"
        "import json\n"
        "overrides = {}\n"
        "if overrides_path and os.path.isfile(overrides_path):\n"
        "    try:\n"
        "        with open(overrides_path, 'r', encoding='utf-8') as f:\n"
        "            overrides = json.load(f)\n"
        "        print('[BlendExport] Property overrides:', list(overrides.keys()))\n"
        "    except Exception as e:\n"
        "        print('[BlendExport] Overrides read (non-fatal):', e)\n"
        "print('[BlendExport] Input blend:', blend_path)\n"
        "print('[BlendExport] Output GLB:', out_glb)\n"
        "print('[BlendExport] Output OBJ:', out_obj)\n"
        "\n"
        "# Discover Properties bone custom properties and write JSON for the app panel (one file per blend).\n"
        "if props_output_path:\n"
        "    try:\n"
        "        prop_list = []\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type != 'ARMATURE' or 'Properties' not in obj.pose.bones:\n"
        "                continue\n"
        "            bone = obj.pose.bones['Properties']\n"
        "            for key in list(getattr(bone, 'keys', lambda: [])()):\n"
        "                if key == '_RNA_UI' or not isinstance(key, str):\n"
        "                    continue\n"
        "                try:\n"
        "                    val = bone[key]\n"
        "                    if not isinstance(val, (int, float)):\n"
        "                        continue\n"
        "                    ui = getattr(bone, 'id_properties_ui', lambda k: None)(key)\n"
        "                    mn = getattr(ui, 'min', 0) if ui is not None else 0\n"
        "                    mx = getattr(ui, 'max', 1) if ui is not None else 1\n"
        "                    if not isinstance(mn, (int, float)): mn = 0\n"
        "                    if not isinstance(mx, (int, float)): mx = 1\n"
        "                    typ = 'int' if isinstance(val, int) else 'float'\n"
        "                    prop_list.append({'name': key, 'label': key, 'type': typ, 'defaultVal': val, 'minVal': mn, 'maxVal': mx})\n"
        "                except Exception:\n"
        "                    pass\n"
        "            break\n"
        "        if prop_list:\n"
        "            with open(props_output_path, 'w', encoding='utf-8') as f:\n"
        "                json.dump(prop_list, f, indent=None)\n"
        "            print('[BlendExport] Wrote', len(prop_list), 'properties to', props_output_path)\n"
        "    except Exception as e:\n"
        "        print('[BlendExport] Props discovery (non-fatal):', e)\n"
        "\n"
        "# Unpack any packed resources (e.g. textures) so they become files next to the .blend.\n"
        "try:\n"
        "    bpy.ops.file.unpack_all(method='WRITE_LOCAL')\n"
        "    print('[BlendExport] Unpacked packed external data (e.g. textures) to files.')\n"
        "except Exception as e:\n"
        "    print('[BlendExport] unpack_all (non-fatal):', e)\n"
        "\n"
        "def unique_preserve(items):\n"
        "    out = []\n"
        "    seen = set()\n"
        "    for i in items:\n"
        "        if i in seen:\n"
        "            continue\n"
        "        seen.add(i)\n"
        "        out.append(i)\n"
        "    return out\n"
        "\n"
        "def safe_file_stem(name):\n"
        "    stem = os.path.splitext(os.path.basename((name or '').replace('\\\\', '/')))[0]\n"
        "    if not stem:\n"
        "        stem = 'tex'\n"
        "    out = []\n"
        "    for ch in stem:\n"
        "        if ch.isalnum() or ch in ('_', '-'):\n"
        "            out.append(ch)\n"
        "        else:\n"
        "            out.append('_')\n"
        "    s = ''.join(out).strip('_')\n"
        "    return s if s else 'tex'\n"
        "\n"
        "def candidate_paths(texture_ref):\n"
        "    ref = texture_ref.strip().strip('\"').strip(\"'\")\n"
        "    if not ref:\n"
        "        return []\n"
        "    cands = [ref]\n"
        "    try:\n"
        "        cands.append(bpy.path.abspath(ref))\n"
        "    except Exception:\n"
        "        pass\n"
        "    cands.append(os.path.join(os.path.dirname(blend_path), ref))\n"
        "    return unique_preserve(cands)\n"
        "\n"
        "def ensure_local_texture(texture_ref, out_dir):\n"
        "    ref = texture_ref.strip().strip('\"').strip(\"'\")\n"
        "    if not ref:\n"
        "        return None\n"
        "    base = os.path.basename(ref.replace('\\\\', '/'))\n"
        "    if not base:\n"
        "        return None\n"
        "    dst = os.path.join(out_dir, base)\n"
        "    if os.path.exists(dst):\n"
        "        return dst\n"
        "\n"
        "    for src in candidate_paths(ref):\n"
        "        if os.path.exists(src):\n"
        "            try:\n"
        "                shutil.copy2(src, dst)\n"
        "                return dst if os.path.exists(dst) else None\n"
        "            except Exception:\n"
        "                pass\n"
        "\n"
        "    for img in bpy.data.images:\n"
        "        if img is None:\n"
        "            continue\n"
        "        img_base = os.path.basename((img.filepath or '').replace('\\\\', '/'))\n"
        "        if not img_base:\n"
        "            img_base = os.path.basename((img.name or '').replace('\\\\', '/'))\n"
        "        if img_base != base:\n"
        "            continue\n"
        "        try:\n"
        "            if getattr(img, 'packed_file', None) is not None:\n"
        "                img.save_render(dst)\n"
        "                if os.path.exists(dst):\n"
        "                    return dst\n"
        "            src_img = bpy.path.abspath(img.filepath)\n"
        "            if src_img and os.path.exists(src_img):\n"
        "                shutil.copy2(src_img, dst)\n"
        "                if os.path.exists(dst):\n"
        "                    return dst\n"
        "        except Exception:\n"
        "            pass\n"
        "\n"
        "    return None\n"
        "\n"
        "def export_all_images_to_png(out_dir):\n"
        "    mapping = {}\n"
        "    for img in bpy.data.images:\n"
        "        if img is None:\n"
        "            continue\n"
        "        src_name = (img.filepath or '').replace('\\\\', '/')\n"
        "        base = os.path.basename(src_name)\n"
        "        if not base:\n"
        "            base = os.path.basename((img.name or '').replace('\\\\', '/'))\n"
        "        if not base:\n"
        "            continue\n"
        "        out_png = os.path.join(out_dir, safe_file_stem(base) + '.png')\n"
        "        try:\n"
        "            img.filepath_raw = out_png\n"
        "            img.file_format = 'PNG'\n"
        "            img.save()\n"
        "            if os.path.exists(out_png):\n"
        "                key_base = base.lower()\n"
        "                key_stem = os.path.splitext(base)[0].lower()\n"
        "                mapping[key_base] = os.path.basename(out_png)\n"
        "                mapping[key_stem] = os.path.basename(out_png)\n"
        "        except Exception:\n"
        "            try:\n"
        "                src_abs = bpy.path.abspath(img.filepath)\n"
        "                if src_abs and os.path.exists(src_abs):\n"
        "                    dst = os.path.join(out_dir, os.path.basename(src_abs))\n"
        "                    if not os.path.exists(dst):\n"
        "                        shutil.copy2(src_abs, dst)\n"
        "                    if os.path.exists(dst):\n"
        "                        key_base = os.path.basename(src_abs).lower()\n"
        "                        key_stem = os.path.splitext(os.path.basename(src_abs))[0].lower()\n"
        "                        mapping[key_base] = os.path.basename(dst)\n"
        "                        mapping[key_stem] = os.path.basename(dst)\n"
        "            except Exception:\n"
        "                pass\n"
        "    return mapping\n"
        "\n"
        "def qt_friendly_texture(path, out_dir):\n"
        "    p = path\n"
        "    ext = os.path.splitext(p)[1].lower()\n"
        "    if ext != '.tga':\n"
        "        return p\n"
        "    png_path = os.path.join(out_dir, os.path.splitext(os.path.basename(p))[0] + '.png')\n"
        "    if os.path.exists(png_path):\n"
        "        return png_path\n"
        "    try:\n"
        "        img = bpy.data.images.load(p, check_existing=True)\n"
        "        img.filepath_raw = png_path\n"
        "        img.file_format = 'PNG'\n"
        "        img.save()\n"
        "        return png_path if os.path.exists(png_path) else p\n"
        "    except Exception:\n"
        "        return p\n"
        "\n"
        "def rewrite_mtl_texture_paths(obj_path):\n"
        "    mtl_path = os.path.splitext(obj_path)[0] + '.mtl'\n"
        "    if not os.path.exists(mtl_path):\n"
        "        return\n"
        "    out_dir = os.path.dirname(mtl_path)\n"
        "    image_map = export_all_images_to_png(out_dir)\n"
        "    lines_out = []\n"
        "    with open(mtl_path, 'r', encoding='utf-8', errors='ignore') as f:\n"
        "        for line in f:\n"
        "            s = line.strip()\n"
        "            if not s or s.startswith('#'):\n"
        "                lines_out.append(line)\n"
        "                continue\n"
        "            parts = s.split(None, 1)\n"
        "            if len(parts) < 2:\n"
        "                lines_out.append(line)\n"
        "                continue\n"
        "            cmd = parts[0].lower()\n"
        "            if cmd.startswith('map_') or cmd in ('bump', 'disp', 'decal', 'refl'):\n"
        "                tex_ref = parts[1].strip()\n"
                "                tex_base = os.path.basename(tex_ref.replace('\\\\', '/')).lower()\n"
                "                tex_stem = os.path.splitext(tex_base)[0]\n"
                "                mapped = image_map.get(tex_base) or image_map.get(tex_stem)\n"
                "                if mapped:\n"
                "                    lines_out.append(parts[0] + ' ' + mapped + '\\n')\n"
                "                    continue\n"
        "                local_tex = ensure_local_texture(tex_ref, out_dir)\n"
        "                if local_tex is not None:\n"
                "                    qt_tex = qt_friendly_texture(local_tex, out_dir)\n"
                "                    lines_out.append(parts[0] + ' ' + os.path.basename(qt_tex) + '\\n')\n"
        "                else:\n"
                "                    # No resolvable texture: drop this map line to avoid hard-failing unresolved absolute refs.\n"
                "                    pass\n"
        "            else:\n"
        "                lines_out.append(line)\n"
        "    with open(mtl_path, 'w', encoding='utf-8', errors='ignore') as f:\n"
        "        f.writelines(lines_out)\n"
        "\n"
        "# Improve texture reliability: resolve external refs from blend directory.\n"
        "# Many .blend files reference textures by relative path (e.g. ../../Fortnite/...).\n"
        "# If that path does not exist, search next to the .blend by filename and repoint.\n"
        "def resolve_external_textures_near_blend():\n"
        "    blend_dir = os.path.dirname(blend_path)\n"
        "    search_dirs = [blend_dir]\n"
        "    for sub in ('textures', 'Texture', 'tex', 'Textures', 'Maps', 'images'):\n"
        "        d = os.path.join(blend_dir, sub)\n"
        "        if os.path.isdir(d):\n"
        "            search_dirs.append(d)\n"
        "    resolved = 0\n"
        "    for img in bpy.data.images:\n"
        "        if img is None:\n"
        "            continue\n"
        "        if getattr(img, 'packed_file', None) is not None:\n"
        "            continue\n"
        "        ref = (img.filepath or '').strip().strip('\"').strip(\"'\")\n"
        "        if not ref:\n"
        "            continue\n"
        "        base = os.path.basename(ref.replace('\\\\', '/'))\n"
        "        if not base:\n"
        "            continue\n"
        "        try:\n"
        "            abs_ref = bpy.path.abspath(ref)\n"
        "            if abs_ref and os.path.exists(abs_ref):\n"
        "                continue\n"
        "        except Exception:\n"
        "            pass\n"
        "        for d in search_dirs:\n"
        "            candidate = os.path.join(d, base)\n"
        "            if os.path.isfile(candidate):\n"
        "                try:\n"
        "                    img.filepath = candidate\n"
        "                    img.reload()\n"
        "                    resolved += 1\n"
        "                except Exception:\n"
        "                    pass\n"
        "                break\n"
        "    print('[BlendExport] Resolved external textures next to blend:', resolved)\n"
        "\n"
        "resolve_external_textures_near_blend()\n"
        "\n"
        "# Set Properties bone custom props from overrides so material drivers (e.g. Skin Roughness -> Fac) evaluate before we simplify materials.\n"
        "def apply_property_overrides_early(overrides_dict):\n"
        "    if not overrides_dict:\n"
        "        return\n"
        "    props_bone_name = None\n"
        "    for arm in bpy.data.armatures:\n"
        "        if 'Properties' in arm.bones:\n"
        "            props_bone_name = 'Properties'\n"
        "            break\n"
        "    if not props_bone_name and getattr(bpy.types, 'BoneCollection', None):\n"
        "        for arm in bpy.data.armatures:\n"
        "            for coll in getattr(arm, 'collections_all', []) or []:\n"
        "                if getattr(coll, 'name', None) == 'Properties' and getattr(coll, 'bones', None):\n"
        "                    for b in coll.bones:\n"
        "                        if b and getattr(b, 'name', None):\n"
        "                            props_bone_name = b.name\n"
        "                            break\n"
        "                    break\n"
        "            if props_bone_name:\n"
        "                break\n"
        "    if props_bone_name:\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type != 'ARMATURE' or not obj.data or props_bone_name not in obj.pose.bones:\n"
        "                continue\n"
        "            pose_bone = obj.pose.bones[props_bone_name]\n"
        "            for key in list(getattr(pose_bone, 'keys', lambda: [])()):\n"
        "                if key == '_RNA_UI' or not isinstance(key, str):\n"
        "                    continue\n"
        "                try:\n"
        "                    cur = pose_bone[key]\n"
        "                    v = overrides_dict.get(key, cur)\n"
        "                    if isinstance(v, str):\n"
        "                        try: v = int(v) if isinstance(cur, int) else float(v)\n"
        "                        except (ValueError, TypeError): v = cur\n"
        "                    pose_bone[key] = int(v) if isinstance(cur, int) else float(v)\n"
        "                except Exception:\n"
        "                    pass\n"
        "            break\n"
        "    try:\n"
        "        bpy.context.view_layer.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "    try:\n"
        "        dg = bpy.context.evaluated_depsgraph_get()\n"
        "        if dg:\n"
        "            dg.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "\n"
        "apply_property_overrides_early(overrides)\n"
        "\n"
        "def simplify_materials_for_gltf():\n"
        "    # glTF only supports Principled BSDF; selector nodes and custom shaders (e.g. FN Shader) don't export.\n"
        "    # 1) Resolve selector-driven base color (e.g. Nails: Texture Selector -> solid color).\n"
        "    # 2) Replace custom group shaders (e.g. Face/Hair FN Shader) with Principled BSDF using diffuse texture.\n"
        "    simplified = 0\n"
        "    for mat in bpy.data.materials:\n"
        "        if mat is None or not getattr(mat, 'node_tree', None):\n"
        "            continue\n"
        "        tree = mat.node_tree\n"
        "        out_node = None\n"
        "        for n in tree.nodes:\n"
        "            if getattr(n, 'type', None) == 'OUTPUT_MATERIAL':\n"
        "                out_node = n\n"
        "                break\n"
        "        if not out_node or not out_node.inputs['Surface'].links:\n"
        "            continue\n"
        "        surf_link = out_node.inputs['Surface'].links[0]\n"
        "        surf_node = surf_link.from_node\n"
        "        surf_sock = surf_link.from_socket\n"
        "\n"
        "        if getattr(surf_node, 'type', None) == 'GROUP':\n"
        "            # Custom shader group (e.g. FN Shader): use ONLY diffuse/albedo image, never normal/spec/emission.\n"
        "            def is_non_diffuse_socket(name):\n"
        "                n = (name or '').lower()\n"
        "                if '_n' in n or 'normal' in n or 'norm' in n or '_s' in n or 'spec' in n:\n"
        "                    return True\n"
        "                if '_e' in n or 'emission' in n or 'roughness' in n or 'metallic' in n:\n"
        "                    return True\n"
        "                if 'ao' in n or 'occlusion' in n or '_m' in n and 'mask' not in n:\n"
        "                    return True\n"
        "                return False\n"
        "            img_node = None\n"
        "            fallback_node = None\n"
        "            for inp in surf_node.inputs:\n"
        "                if not inp.links:\n"
        "                    continue\n"
        "                from_node = inp.links[0].from_node\n"
        "                if getattr(from_node, 'type', None) != 'TEX_IMAGE' or not getattr(from_node, 'image', None):\n"
        "                    continue\n"
        "                if is_non_diffuse_socket(inp.name):\n"
        "                    continue\n"
        "                name = (inp.name or '').lower()\n"
        "                if '_d' in name or 'diffuse' in name or 'albedo' in name or ('base' in name and 'color' in name):\n"
        "                    img_node = from_node\n"
        "                    break\n"
        "                if fallback_node is None:\n"
        "                    fallback_node = from_node\n"
        "            if img_node is None:\n"
        "                img_node = fallback_node\n"
        "            if img_node and img_node.image:\n"
        "                bsdf = tree.nodes.new('ShaderNodeBsdfPrincipled')\n"
        "                bsdf.location = (surf_node.location.x - 280, surf_node.location.y)\n"
        "                tree.links.new(bsdf.inputs['Base Color'], img_node.outputs['Color'])\n"
        "                roughness_val = 0.5\n"
        "                for inp in surf_node.inputs:\n"
        "                    name = (inp.name or '').lower()\n"
        "                    if 'rough' not in name and name not in ('fac', 'value', 'factor'):\n"
        "                        continue\n"
        "                    try:\n"
        "                        if inp.links:\n"
        "                            from_sock = inp.links[0].from_socket\n"
        "                            if hasattr(from_sock, 'default_value'):\n"
        "                                v = from_sock.default_value\n"
        "                            else:\n"
        "                                v = getattr(inp.links[0].from_node.outputs[0], 'default_value', 0.5)\n"
        "                        else:\n"
        "                            v = getattr(inp, 'default_value', 0.5)\n"
        "                        if hasattr(v, '__len__') and len(v) > 0:\n"
        "                            v = v[0] if hasattr(v, '__getitem__') else v\n"
        "                        roughness_val = max(0.0, min(1.0, float(v)))\n"
        "                        break\n"
        "                    except Exception:\n"
        "                        pass\n"
        "                try:\n"
        "                    bsdf.inputs['Roughness'].default_value = roughness_val\n"
        "                except Exception:\n"
        "                    pass\n"
        "                tree.links.remove(surf_link)\n"
        "                tree.links.new(out_node.inputs['Surface'], bsdf.outputs['BSDF'])\n"
        "                simplified += 1\n"
        "            continue\n"
        "\n"
        "        if getattr(surf_node, 'type', None) == 'BSDF_PRINCIPLED':\n"
        "            base_link = surf_node.inputs['Base Color'].links\n"
        "            if not base_link:\n"
        "                continue\n"
        "            from_node = base_link[0].from_node\n"
        "            if getattr(from_node, 'type', None) != 'GROUP':\n"
        "                continue\n"
        "            grp = from_node\n"
        "            idx_input = None\n"
        "            tex_inputs = []\n"
        "            for inp in grp.inputs:\n"
        "                name = (inp.name or '').lower()\n"
        "                if 'number' in name or 'index' in name or 'selector' in name or 'value' in name:\n"
        "                    idx_input = inp\n"
        "                if 'texture' in name or 'color' in name:\n"
        "                    tex_inputs.append((inp.name, inp))\n"
        "            if idx_input is None or not tex_inputs:\n"
        "                continue\n"
        "            try:\n"
        "                idx = 0\n"
        "                if idx_input.links:\n"
        "                    vnode = idx_input.links[0].from_node\n"
        "                    if getattr(vnode, 'type', None) == 'VALUE':\n"
        "                        idx = int(round(vnode.outputs[0].default_value))\n"
        "                    elif getattr(vnode, 'outputs', None) and len(vnode.outputs):\n"
        "                        idx = int(round(vnode.outputs[0].default_value))\n"
        "                else:\n"
        "                    idx = int(round(idx_input.default_value))\n"
        "                tex_inputs.sort(key=lambda x: x[0])\n"
        "                idx = max(0, min(idx - 1, len(tex_inputs) - 1))\n"
        "                chosen = tex_inputs[idx][1]\n"
        "                color = (0.5, 0.5, 0.5, 1.0)\n"
        "                if chosen.links:\n"
        "                    cnode = chosen.links[0].from_node\n"
        "                    if getattr(cnode, 'type', None) == 'RGB':\n"
        "                        color = (*list(cnode.outputs[0].default_value)[:3], 1.0)\n"
        "                    elif hasattr(cnode, 'outputs') and len(cnode.outputs) and hasattr(cnode.outputs[0], 'default_value'):\n"
        "                        val = cnode.outputs[0].default_value\n"
        "                        if hasattr(val, '__len__') and len(val) >= 3:\n"
        "                            color = (*list(val)[:3], 1.0)\n"
        "                else:\n"
        "                    if hasattr(chosen, 'default_value') and hasattr(chosen.default_value, '__len__') and len(chosen.default_value) >= 3:\n"
        "                        color = (*list(chosen.default_value)[:3], 1.0)\n"
        "                surf_node.inputs['Base Color'].default_value = color\n"
        "                tree.links.remove(base_link[0])\n"
        "                simplified += 1\n"
        "            except Exception:\n"
        "                pass\n"
        "    print('[BlendExport] Simplified materials for glTF:', simplified)\n"
        "\n"
        "def prepare_material_export_flags():\n"
        "    changed = 0\n"
        "    for mat in bpy.data.materials:\n"
        "        if mat is None:\n"
        "            continue\n"
        "        try:\n"
        "            if getattr(mat, 'use_backface_culling', False):\n"
        "                mat.use_backface_culling = False\n"
        "                changed += 1\n"
        "        except Exception:\n"
        "            pass\n"
        "    print('[BlendExport] Disabled backface culling on materials:', changed)\n"
        "\n"
        "def convert_unsupported_lights_for_gltf():\n"
        "    converted = 0\n"
        "    for light in bpy.data.lights:\n"
        "        if light is None:\n"
        "            continue\n"
        "        try:\n"
        "            if light.type == 'AREA':\n"
        "                # glTF exporter does not support AREA lights; convert to POINT for compatibility.\n"
        "                light.type = 'POINT'\n"
        "                converted += 1\n"
        "        except Exception:\n"
        "            pass\n"
        "    print('[BlendExport] Converted AREA lights for glTF:', converted)\n"
        "\n"
        "def select_exportables():\n"
        "    try:\n"
        "        if bpy.ops.object.mode_set.poll():\n"
        "            bpy.ops.object.mode_set(mode='OBJECT')\n"
        "    except Exception:\n"
        "        pass\n"
        "    for obj in bpy.data.objects:\n"
        "        obj.select_set(False)\n"
        "    export_types = {'MESH', 'CURVE', 'SURFACE', 'META', 'FONT', 'ARMATURE', 'LIGHT', 'CAMERA', 'EMPTY'}\n"
        "    selected = []\n"
        "    for obj in bpy.data.objects:\n"
        "        if obj.type in export_types:\n"
        "            obj.select_set(True)\n"
        "            selected.append(obj)\n"
        "    if not selected:\n"
        "        for obj in bpy.data.objects:\n"
        "            obj.select_set(True)\n"
        "            selected.append(obj)\n"
        "    if selected:\n"
        "        bpy.context.view_layer.objects.active = selected[0]\n"
        "    type_counts = {}\n"
        "    for obj in selected:\n"
        "        t = obj.type\n"
        "        type_counts[t] = type_counts.get(t, 0) + 1\n"
        "    print('[BlendExport] Selected object count:', len(selected), 'type_counts:', type_counts)\n"
        "    return len(selected) > 0\n"
        "\n"
        "def select_exportables_for_base(togglable_mesh_names, body_mesh_names):\n"
        "    # Base GLB: everything except togglable parts and except body (body only in part GLBs so user gets the wanted body).\n"
        "    for obj in bpy.data.objects:\n"
        "        obj.select_set(False)\n"
        "    export_types = {'MESH', 'CURVE', 'SURFACE', 'META', 'FONT', 'ARMATURE', 'LIGHT', 'CAMERA', 'EMPTY'}\n"
        "    for obj in bpy.data.objects:\n"
        "        if obj.type not in export_types:\n"
        "            continue\n"
        "        if obj.type == 'MESH' and (obj.name or '') in togglable_mesh_names:\n"
        "            continue\n"
        "        if obj.type == 'MESH' and (obj.name or '') in body_mesh_names:\n"
        "            continue\n"
        "        obj.select_set(True)\n"
        "    print('[BlendExport] Selected for base (excluding togglable and body meshes)')\n"
        "\n"
        "def select_exportables_for_part(part_mesh_names, base_mesh_names):\n"
        "    # Part GLBs: armature + base (body, head, etc.) + part meshes so body comes from parts and modifiers evaluate.\n"
        "    for obj in bpy.data.objects:\n"
        "        obj.select_set(False)\n"
        "    for obj in bpy.data.objects:\n"
        "        if obj.type == 'ARMATURE':\n"
        "            obj.select_set(True)\n"
        "        elif obj.type == 'MESH':\n"
        "            n = obj.name or ''\n"
        "            if n in base_mesh_names or n in part_mesh_names:\n"
        "                obj.select_set(True)\n"
        "    print('[BlendExport] Selected for part:', len(part_mesh_names), 'meshes (armature + base + part)')\n"
        "\n"
        "def reload_images_for_export():\n"
        "    # After unpack, image datablocks may have no pixel data; reload from disk so export works.\n"
        "    reloaded = 0\n"
        "    for img in bpy.data.images:\n"
        "        if img is None:\n"
        "            continue\n"
        "        try:\n"
        "            path = bpy.path.abspath(img.filepath_raw or img.filepath or '')\n"
        "            if path and os.path.isfile(path):\n"
        "                if img.size[0] == 0 or img.size[1] == 0:\n"
        "                    img.reload()\n"
        "                    reloaded += 1\n"
        "        except Exception:\n"
        "            pass\n"
        "    print('[BlendExport] Reloaded images from disk:', reloaded)\n"
        "\n"
        "def ensure_images_png_for_gltf(out_dir):\n"
        "    # Convert TGA/packed images to PNG in cache dir so GLB embed and viewers display correctly.\n"
        "    converted = 0\n"
        "    for i, img in enumerate(bpy.data.images):\n"
        "        if img is None:\n"
        "            continue\n"
        "        fp = (img.filepath_raw or img.filepath or '').replace('\\\\', '/')\n"
        "        ext = os.path.splitext(fp)[1].lower()\n"
        "        is_packed = getattr(img, 'packed_file', None) is not None\n"
        "        if ext in ('.png', '.jpg', '.jpeg') and not is_packed:\n"
        "            continue\n"
        "        try:\n"
        "            path = bpy.path.abspath(fp)\n"
        "            if path and os.path.isfile(path) and (img.size[0] == 0 or img.size[1] == 0):\n"
        "                img.reload()\n"
        "        except Exception:\n"
        "            pass\n"
        "        base = (img.name or os.path.basename(fp) or 'image').replace(' ', '_')\n"
        "        safe = safe_file_stem(base) + '_' + str(i) + '.png'\n"
        "        out_png = os.path.join(out_dir, safe)\n"
        "        try:\n"
        "            img.filepath_raw = out_png\n"
        "            img.file_format = 'PNG'\n"
        "            img.save()\n"
        "            if os.path.exists(out_png):\n"
        "                img.reload()\n"
        "                converted += 1\n"
        "        except Exception:\n"
        "            pass\n"
        "    print('[BlendExport] Converted images to PNG for GLB:', converted)\n"
        "\n"
        "def gltf_export_with_fallback(filepath):\n"
        "    kwargs = {\n"
        "        'filepath': filepath,\n"
        "        'export_format': 'GLB',\n"
        "        'use_selection': True,\n"
        "        'export_apply': True,\n"
        "        'export_texcoords': True,\n"
        "        'export_normals': True,\n"
        "        'export_tangents': True,\n"
        "        'export_materials': 'EXPORT',\n"
        "        'export_image_format': 'AUTO',\n"
        "        'export_keep_originals': False,\n"
        "        'export_animations': False,\n"
        "        'export_animation_mode': 'ACTIONS',\n"
        "        'export_frame_range': False,\n"
        "        'export_frame_step': 1,\n"
        "        'export_force_sampling': False,\n"
        "        'export_skins': True,\n"
        "        'export_morph': True,\n"
        "        'export_morph_normal': True,\n"
        "        'export_morph_tangent': True,\n"
        "        'export_cameras': True,\n"
        "        'export_lights': True,\n"
        "        'export_extras': True,\n"
        "        'export_yup': True,\n"
        "        'export_current_frame': True,\n"
        "        'export_rest_position_armature': False\n"
        "    }\n"
        "    while True:\n"
        "        try:\n"
        "            bpy.ops.export_scene.gltf(**kwargs)\n"
        "            return\n"
        "        except TypeError as e:\n"
        "            msg = str(e)\n"
        "            removed = False\n"
        "            for key in list(kwargs.keys()):\n"
        "                if ('unexpected keyword argument' in msg or 'keyword' in msg) and (\"'\" + key + \"'\") in msg:\n"
        "                    kwargs.pop(key, None)\n"
        "                    removed = True\n"
        "                    break\n"
        "            if not removed:\n"
        "                raise\n"
        "\n"
        "simplify_materials_for_gltf()\n"
        "prepare_material_export_flags()\n"
        "convert_unsupported_lights_for_gltf()\n"
        "select_exportables()\n"
        "glb_dir = os.path.dirname(out_glb)\n"
        "os.makedirs(glb_dir, exist_ok=True)\n"
        "reload_images_for_export()\n"
        "ensure_images_png_for_gltf(glb_dir)\n"
        "\n"
        "def apply_visibility_driver_defaults(overrides_dict):\n"
        "    import re\n"
        "    # Set custom properties (Boots, Jacket, etc.) from overrides or defaults so visibility drivers evaluate at export.\n"
        "    int_one = ('Belt', 'Boots', 'Gloves', 'Shorts', 'Skirt', 'Belt Pouch', 'Gun And', 'Knife And', 'Futa Dick')\n"
        "    def value_for(key, current_val, is_int_one):\n"
        "        if key in overrides_dict:\n"
        "            v = overrides_dict[key]\n"
        "            return int(v) if isinstance(current_val, int) else float(v)\n"
        "        if is_int_one:\n"
        "            return 1 if isinstance(current_val, int) else 1.0\n"
        "        return current_val\n"
        "    for obj in bpy.data.objects:\n"
        "        try:\n"
        "            keys = list(getattr(obj, 'keys', lambda: [])())\n"
        "        except Exception:\n"
        "            keys = []\n"
        "        for key in keys:\n"
        "            if key == '_RNA_UI' or not isinstance(key, str):\n"
        "                continue\n"
        "            try:\n"
        "                val = obj[key]\n"
        "                if isinstance(val, (int, float)):\n"
        "                    is_io = any(key.startswith(p) or key == p for p in int_one)\n"
        "                    obj[key] = value_for(key, val, is_io)\n"
        "            except Exception:\n"
        "                pass\n"
        "    for arm in bpy.data.armatures:\n"
        "        for bone in arm.bones:\n"
        "            try:\n"
        "                keys = list(getattr(bone, 'keys', lambda: [])())\n"
        "            except Exception:\n"
        "                keys = []\n"
        "            for key in keys:\n"
        "                if key == '_RNA_UI' or not isinstance(key, str):\n"
        "                    continue\n"
        "                try:\n"
        "                    val = bone[key]\n"
        "                    if isinstance(val, (int, float)):\n"
        "                        is_io = any(key.startswith(p) or key == p for p in int_one)\n"
        "                        bone[key] = value_for(key, val, is_io)\n"
        "                except Exception:\n"
        "                    pass\n"
        "    try:\n"
        "        bpy.context.view_layer.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "    try:\n"
        "        scene = bpy.context.scene\n"
        "        scene.frame_set(1)\n"
        "        scene.frame_set(0)\n"
        "    except Exception:\n"
        "        pass\n"
        "    try:\n"
        "        dg = bpy.context.evaluated_depsgraph_get()\n"
        "        if dg:\n"
        "            dg.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "    # Properties bone: custom props (Boots, Belt, etc.) live on the Properties bone; drive shape keys on Body etc.\n"
        "    # 1) Set pose-bone custom props on armature object(s) so drivers see them; 2) Apply shape key values from overrides (drivers often fail in background).\n"
        "    props_bone_name = None\n"
        "    for arm in bpy.data.armatures:\n"
        "        if 'Properties' in arm.bones:\n"
        "            props_bone_name = 'Properties'\n"
        "            break\n"
        "    if not props_bone_name and getattr(bpy.types, 'BoneCollection', None):\n"
        "        for arm in bpy.data.armatures:\n"
        "            for coll in getattr(arm, 'collections_all', []) or []:\n"
        "                if getattr(coll, 'name', None) == 'Properties' and getattr(coll, 'bones', None):\n"
        "                    for b in coll.bones:\n"
        "                        if b and getattr(b, 'name', None):\n"
        "                            props_bone_name = b.name\n"
        "                            break\n"
        "                    break\n"
        "            if props_bone_name:\n"
        "                break\n"
        "    if props_bone_name:\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type != 'ARMATURE' or not obj.data or props_bone_name not in obj.pose.bones:\n"
        "                continue\n"
        "            pose_bone = obj.pose.bones[props_bone_name]\n"
        "            for key in list(getattr(pose_bone, 'keys', lambda: [])()):\n"
        "                if key == '_RNA_UI' or not isinstance(key, str):\n"
        "                    continue\n"
        "                try:\n"
        "                    cur = pose_bone[key]\n"
        "                    v = overrides_dict.get(key, cur)\n"
        "                    if isinstance(v, str):\n"
        "                        try: v = int(v) if isinstance(cur, int) else float(v)\n"
        "                        except (ValueError, TypeError): v = cur\n"
        "                    pose_bone[key] = int(v) if isinstance(cur, int) else float(v)\n"
        "                except Exception:\n"
        "                    pass\n"
        "    # Build visibility map: property name -> list of mesh object names (for instant toggles in viewer).\n"
        "    visibility_map = {}\n"
        "    if visibility_map_path and props_bone_name:\n"
        "        try:\n"
        "            for mesh_obj in bpy.data.objects:\n"
        "                if mesh_obj.type != 'MESH' or not getattr(mesh_obj, 'animation_data', None) or not mesh_obj.animation_data.drivers:\n"
        "                    continue\n"
        "                for fc in mesh_obj.animation_data.drivers:\n"
        "                    dp = getattr(fc, 'data_path', '') or ''\n"
        "                    if dp not in ('hide_viewport', 'hide_render'):\n"
        "                        continue\n"
        "                    dr = getattr(fc, 'driver', None)\n"
        "                    if not dr or not getattr(dr, 'variables', None):\n"
        "                        continue\n"
        "                    for v in dr.variables:\n"
        "                        try:\n"
        "                            tid = getattr(v, 'targets', [None])[0] if getattr(v, 'targets', None) else None\n"
        "                            if not tid or not getattr(tid, 'data_path', ''):\n"
        "                                continue\n"
        "                            tdp = (tid.data_path or '').strip()\n"
        "                            m2 = re.search(r\"pose\\.bones\\[['\\\"]([^'\\\"]+)['\\\"]\\]\\[['\\\"]([^'\\\"]+)['\\\"]\\]\", tdp)\n"
        "                            if not m2:\n"
        "                                continue\n"
        "                            bn, pk = m2.group(1), m2.group(2)\n"
        "                            if bn != props_bone_name:\n"
        "                                continue\n"
        "                            if pk not in visibility_map:\n"
        "                                visibility_map[pk] = []\n"
        "                            if mesh_obj.name not in visibility_map[pk]:\n"
        "                                visibility_map[pk].append(mesh_obj.name)\n"
        "                            break\n"
        "                        except Exception:\n"
        "                            pass\n"
        "            with open(visibility_map_path, 'w', encoding='utf-8') as f:\n"
        "                json.dump(visibility_map, f, indent=None)\n"
        "            print('[BlendExport] Wrote visibility map:', len(visibility_map), 'properties ->', sum(len(v) for v in visibility_map.values()), 'meshes')\n"
        "        except Exception as e:\n"
        "            print('[BlendExport] Visibility map (non-fatal):', e)\n"
        "    # Apply shape key values from Properties bone / overrides (discover drivers: shape key <- bone custom prop).\n"
        "    # This makes every property in the panel actually change geometry (shape keys), not just Boots.\n"
        "    def prop_name_from_driver_target(tid, tdp):\n"
        "        if not tid or not tdp:\n"
        "            return None\n"
        "        is_arm = getattr(tid, 'type', None) == 'ARMATURE' or (hasattr(tid, 'bones') and hasattr(tid, 'name'))\n"
        "        if not is_arm:\n"
        "            return None\n"
        "        pm = re.search(r\"pose\\.bones\\[([\\\"'])([^\\\"']+)\\\\1\\]\\[([\\\"'])([^\\\"']+)\\\\3\\]\", tdp)\n"
        "        if pm and pm.group(2) == (props_bone_name or ''):\n"
        "            return pm.group(4)\n"
        "        pm = re.search(r\"bones\\[([\\\"'])([^\\\"']+)\\\\1\\]\\[([\\\"'])([^\\\"']+)\\\\3\\]\", tdp)\n"
        "        if pm and pm.group(2) == (props_bone_name or ''):\n"
        "            return pm.group(4)\n"
        "        return None\n"
        "    for mesh_obj in bpy.data.objects:\n"
        "        if mesh_obj.type != 'MESH' or not mesh_obj.data:\n"
        "            continue\n"
        "        sk = getattr(mesh_obj.data, 'shape_keys', None)\n"
        "        if not sk or not getattr(sk, 'animation_data', None) or not getattr(sk.animation_data, 'drivers', None):\n"
        "            continue\n"
        "        for fc in sk.animation_data.drivers:\n"
        "            dp = getattr(fc, 'data_path', '') or ''\n"
        "            m = re.search(r\"key_blocks\\[([\\\"'])([^\\\"']+)\\\\1\\]\\.value\", dp)\n"
        "            if not m:\n"
        "                continue\n"
        "            key_name = m.group(2)\n"
        "            if key_name not in sk.key_blocks:\n"
        "                continue\n"
        "            prop_name = None\n"
        "            dr = getattr(fc, 'driver', None)\n"
        "            if dr and getattr(dr, 'variables', None):\n"
        "                for v in dr.variables:\n"
        "                    for t in getattr(v, 'targets', []) or []:\n"
        "                        prop_name = prop_name_from_driver_target(getattr(t, 'id', None), getattr(t, 'data_path', '') or '')\n"
        "                        if prop_name is not None:\n"
        "                            break\n"
        "                    if prop_name is not None:\n"
        "                        break\n"
        "            if prop_name is None:\n"
        "                continue\n"
        "            val = overrides_dict.get(prop_name)\n"
        "            if val is None and props_bone_name:\n"
        "                for obj in bpy.data.objects:\n"
        "                    if obj.type == 'ARMATURE' and obj.data and props_bone_name in obj.pose.bones:\n"
        "                        try:\n"
        "                            val = obj.pose.bones[props_bone_name][prop_name]\n"
        "                        except Exception:\n"
        "                            pass\n"
        "                        break\n"
        "            if val is not None:\n"
        "                try:\n"
        "                    f = float(val)\n"
        "                    sk.key_blocks[key_name].value = max(0.0, min(1.0, f))\n"
        "                    print('[BlendExport] Shape key:', mesh_obj.name, key_name, '<-', prop_name, '=', sk.key_blocks[key_name].value)\n"
        "                except Exception:\n"
        "                    pass\n"
        "    # Fallback: set shape keys by name for every property (driver discovery often misses in background).\n"
        "    # Match: exact name, \"Prop Fit\", \"Prop_Thing\", or any shape key whose name starts with the property name.\n"
        "    def shape_key_matches_prop(key_name, prop_name):\n"
        "        if not key_name or not prop_name or key_name == 'Basis':\n"
        "            return False\n"
        "        kl = key_name.lower().replace(' ', '')\n"
        "        pl = (prop_name or '').lower().replace(' ', '')\n"
        "        if not pl:\n"
        "            return False\n"
        "        if kl == pl:\n"
        "            return True\n"
        "        if kl == pl + 'fit' or kl.startswith(pl + 'fit'):\n"
        "            return True\n"
        "        if kl.startswith(pl + '_') or (key_name.lower().startswith(prop_name.lower() + ' ') or key_name.lower().startswith(prop_name.lower() + '_')):\n"
        "            return True\n"
        "        if len(pl) >= 2 and kl.startswith(pl) and (len(kl) == len(pl) or (len(kl) > len(pl) and kl[len(pl):len(pl)+1] in ' _')):\n"
        "            return True\n"
        "        if kl.startswith(pl) and len(kl) > len(pl):\n"
        "            return True\n"
        "        return False\n"
        "    def _numeric_val(v):\n"
        "        if isinstance(v, (int, float)):\n"
        "            return float(v)\n"
        "        if isinstance(v, str):\n"
        "            try:\n"
        "                return float(v)\n"
        "            except (ValueError, TypeError):\n"
        "                pass\n"
        "        return None\n"
        "    for prop_name, val in overrides_dict.items():\n"
        "        f = _numeric_val(val)\n"
        "        if f is None:\n"
        "            continue\n"
        "        f = max(0.0, min(1.0, f))\n"
        "        for mesh_obj in bpy.data.objects:\n"
        "            if mesh_obj.type != 'MESH' or not mesh_obj.data:\n"
        "                continue\n"
        "            sk = getattr(mesh_obj.data, 'shape_keys', None)\n"
        "            if not sk or not sk.key_blocks:\n"
        "                continue\n"
        "            for key_name in list(sk.key_blocks.keys()):\n"
        "                if not shape_key_matches_prop(key_name, prop_name):\n"
        "                    continue\n"
        "                try:\n"
        "                    sk.key_blocks[key_name].value = f\n"
        "                    print('[BlendExport] Shape key:', mesh_obj.name, key_name, '<-', prop_name, '=', f)\n"
        "                except Exception:\n"
        "                    pass\n"
        "    try:\n"
        "        bpy.context.view_layer.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "    try:\n"
        "        dg2 = bpy.context.evaluated_depsgraph_get()\n"
        "        if dg2:\n"
        "            dg2.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "    if not overrides_dict:\n"
        "        pass\n"
        "    else:\n"
        "        boots_on = overrides_dict.get('Boots', 1)\n"
        "        if isinstance(boots_on, str):\n"
        "            try: boots_on = float(boots_on)\n"
        "            except (ValueError, TypeError): boots_on = 1\n"
        "        if not isinstance(boots_on, (int, float)):\n"
        "            boots_on = 1\n"
        "        boots_on = 1 if boots_on else 0\n"
        "        leg_name_keywords = ('boot', 'leg', 'foot', 'calf', 'shin')\n"
        "        def modifier_affects_legs(mod):\n"
        "            name_lower = (getattr(mod, 'name', None) or '').lower()\n"
        "            if any(k in name_lower for k in leg_name_keywords):\n"
        "                return True\n"
        "            if 'mask' in name_lower and ('leg' in name_lower or 'boot' in name_lower or 'foot' in name_lower):\n"
        "                return True\n"
        "            vg = getattr(mod, 'vertex_group', None) or ''\n"
        "            if isinstance(vg, str):\n"
        "                vg_lower = vg.lower()\n"
        "                if any(k in vg_lower for k in ('leg', 'boot', 'foot', 'calf', 'shin')):\n"
        "                    return True\n"
        "            return False\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type != 'MESH' or not getattr(obj, 'modifiers', None):\n"
        "                continue\n"
        "            for mod in obj.modifiers:\n"
        "                if not mod:\n"
        "                    continue\n"
        "                if not modifier_affects_legs(mod):\n"
        "                    continue\n"
        "                try:\n"
        "                    mod.show_viewport = bool(boots_on)\n"
        "                    mod.show_render = bool(boots_on)\n"
        "                    print('[BlendExport] Boots/leg modifier:', obj.name, mod.name, 'show_viewport=', boots_on)\n"
        "                    if hasattr(obj.modifiers, 'update'):\n"
        "                        obj.modifiers.update()\n"
        "                    if hasattr(obj, 'update_tag'):\n"
        "                        obj.update_tag()\n"
        "                except Exception:\n"
        "                    pass\n"
        "        try:\n"
        "            bpy.context.view_layer.update()\n"
        "        except Exception:\n"
        "            pass\n"
        "        try:\n"
        "            dg_mod = bpy.context.evaluated_depsgraph_get()\n"
        "            if dg_mod:\n"
        "                dg_mod.update()\n"
        "        except Exception:\n"
        "            pass\n"
        "        # Also enable modifier visibility when driven by Boots etc. (driver may be on modifiers[\"X\"].show_viewport).\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type != 'MESH' or not getattr(obj, 'animation_data', None) or not obj.animation_data.drivers:\n"
        "                continue\n"
        "            for fc in obj.animation_data.drivers:\n"
        "                dp = getattr(fc, 'data_path', '') or ''\n"
        "                if 'modifiers[' not in dp or '\"].show_' not in dp:\n"
        "                    continue\n"
        "                m = re.search(r'modifiers\\[\"([^\"]+)\"\\]\\.show_(viewport|render)', dp)\n"
        "                if not m:\n"
        "                    continue\n"
        "                mod_name, prop = m.group(1), m.group(2)\n"
        "                if mod_name not in obj.modifiers:\n"
        "                    continue\n"
        "                mod = obj.modifiers[mod_name]\n"
        "                dr = getattr(fc, 'driver', None)\n"
        "                if not dr or not getattr(dr, 'variables', None):\n"
        "                    continue\n"
        "                var_val = 0\n"
        "                for v in dr.variables:\n"
        "                    try:\n"
        "                        tid = getattr(v, 'targets', [None])[0] if getattr(v, 'targets', None) else None\n"
        "                        if not tid or not getattr(tid, 'id', None) or not getattr(tid, 'data_path', ''):\n"
        "                            continue\n"
        "                        pid = tid.id\n"
        "                        dp = (tid.data_path or '').strip()\n"
        "                        m2 = re.search(r\"pose\\.bones\\[['\\\"]([^'\\\"]+)['\\\"]\\]\\[['\\\"]([^'\\\"]+)['\\\"]\\]\", dp)\n"
        "                        if m2:\n"
        "                            bone_name, prop_key = m2.group(1), m2.group(2)\n"
        "                            arm_obj = pid if getattr(pid, 'pose', None) else None\n"
        "                            if not arm_obj and getattr(pid, 'bones', None):\n"
        "                                for o in bpy.data.objects:\n"
        "                                    if o.type == 'ARMATURE' and getattr(o, 'data', None) == pid and getattr(o, 'pose', None):\n"
        "                                        arm_obj = o\n"
        "                                        break\n"
        "                            if arm_obj and bone_name in arm_obj.pose.bones and prop_key in arm_obj.pose.bones[bone_name]:\n"
        "                                var_val = 1 if arm_obj.pose.bones[bone_name][prop_key] else 0\n"
        "                                break\n"
        "                        p = dp.strip('[]').strip('\"').strip(\"'\")\n"
        "                        if p and hasattr(pid, '__getitem__') and p in pid:\n"
        "                            var_val = 1 if pid[p] else 0\n"
        "                            break\n"
        "                    except Exception:\n"
        "                        pass\n"
        "                expr = (getattr(dr, 'expression', None) or '').strip()\n"
        "                # In many blends: prop=0 means show, prop=1 means hide (inverted vs plain 'var').\n"
        "                if '1-' in expr.replace(' ', '') or '1 -' in expr or ('not ' in expr and 'var' in expr):\n"
        "                    show_val = 1 if var_val else 0\n"
        "                else:\n"
        "                    show_val = 0 if var_val else 1\n"
        "                try:\n"
        "                    if prop == 'viewport':\n"
        "                        mod.show_viewport = bool(show_val)\n"
        "                    else:\n"
        "                        mod.show_render = bool(show_val)\n"
        "                except Exception:\n"
        "                    pass\n"
        "        # Fallback: when drivers are invalid (e.g. in background), apply bone hide by interpreting drivers.\n"
        "        # Drivers on pose.bones[\"x\"].hide[0] often use var = armature[\"Boots\"] with expression \"var\" (hide when Boots=1) or \"1-var\" (show when Boots=1).\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type != 'ARMATURE' or not getattr(obj, 'animation_data', None) or not obj.animation_data.drivers:\n"
        "                continue\n"
        "            pose = obj.pose\n"
        "            for fc in obj.animation_data.drivers:\n"
        "                dp = getattr(fc, 'data_path', '') or ''\n"
        "                if '.hide' not in dp or 'pose.bones[' not in dp:\n"
        "                    continue\n"
        "                m = re.search(r\"pose\\.bones\\[['\\\"]([^'\\\"]+)['\\\"]\\]\\.hide(?:\\[(\\d+)\\])?\", dp)\n"
        "                if not m:\n"
        "                    continue\n"
        "                bone_name = m.group(1)\n"
        "                hidx = int(m.group(2)) if m.group(2) is not None else getattr(fc, 'array_index', 0)\n"
        "                if bone_name not in pose.bones:\n"
        "                    continue\n"
        "                bone = pose.bones[bone_name]\n"
        "                dr = getattr(fc, 'driver', None)\n"
        "                if not dr or not getattr(dr, 'variables', None):\n"
        "                    continue\n"
        "                expr = (getattr(dr, 'expression', None) or '').strip()\n"
        "                var_val = 1\n"
        "                for v in dr.variables:\n"
        "                    try:\n"
        "                        tid = getattr(v, 'targets', [None])[0] if getattr(v, 'targets', None) else None\n"
        "                        if not tid or not getattr(tid, 'data_path', ''):\n"
        "                            continue\n"
        "                        pid = getattr(tid, 'id', None)\n"
        "                        dp = (tid.data_path or '').strip()\n"
        "                        arm_obj = obj if pid == obj else (obj if getattr(obj, 'data', None) == pid else None)\n"
        "                        if not arm_obj or not getattr(arm_obj, 'pose', None):\n"
        "                            continue\n"
        "                        m2 = re.search(r\"pose\\.bones\\[['\\\"]([^'\\\"]+)['\\\"]\\]\\[['\\\"]([^'\\\"]+)['\\\"]\\]\", dp)\n"
        "                        if m2:\n"
        "                            bn, pk = m2.group(1), m2.group(2)\n"
        "                            if bn in arm_obj.pose.bones and pk in arm_obj.pose.bones[bn]:\n"
        "                                var_val = 1 if arm_obj.pose.bones[bn][pk] else 0\n"
        "                                break\n"
        "                        if pid != obj:\n"
        "                            continue\n"
        "                        p = dp.strip('[]').strip('\"').strip(\"'\")\n"
        "                        if p and hasattr(obj, '__getitem__') and p in obj:\n"
        "                            var_val = 1 if obj[p] else 0\n"
        "                            break\n"
        "                    except Exception:\n"
        "                        pass\n"
        "                # prop=0 -> hide, prop=1 -> show (same as mesh visibility).\n"
        "                if '1-' in expr.replace(' ', '') or '1 -' in expr or ('not ' in expr and 'var' in expr):\n"
        "                    hide_val = 1 if var_val else 0\n"
        "                else:\n"
        "                    hide_val = 0 if var_val else 1\n"
        "                try:\n"
        "                    h = list(bone.hide)\n"
        "                    if hidx < len(h):\n"
        "                        h[hidx] = bool(hide_val)\n"
        "                        bone.hide = h\n"
        "                except Exception:\n"
        "                    try:\n"
        "                        if hidx == 0:\n"
        "                            bone.hide_viewport = bool(hide_val)\n"
        "                    except Exception:\n"
        "                        pass\n"
        "        # Object visibility: only when a mesh's hide is driven by Properties bone AND we resolved the variable, apply it.\n"
        "        for mesh_obj in bpy.data.objects:\n"
        "            if mesh_obj.type != 'MESH' or not getattr(mesh_obj, 'animation_data', None) or not mesh_obj.animation_data.drivers:\n"
        "                continue\n"
        "            for fc in mesh_obj.animation_data.drivers:\n"
        "                dp = getattr(fc, 'data_path', '') or ''\n"
        "                if dp not in ('hide_viewport', 'hide_render'):\n"
        "                    continue\n"
        "                dr = getattr(fc, 'driver', None)\n"
        "                if not dr or not getattr(dr, 'variables', None):\n"
        "                    continue\n"
        "                var_val = None\n"
        "                for v in dr.variables:\n"
        "                    try:\n"
        "                        tid = getattr(v, 'targets', [None])[0] if getattr(v, 'targets', None) else None\n"
        "                        if not tid or not getattr(tid, 'data_path', ''):\n"
        "                            continue\n"
        "                        pid = getattr(tid, 'id', None)\n"
        "                        tdp = (tid.data_path or '').strip()\n"
        "                        m2 = re.search(r\"pose\\.bones\\[['\\\"]([^'\\\"]+)['\\\"]\\]\\[['\\\"]([^'\\\"]+)['\\\"]\\]\", tdp)\n"
        "                        if not m2:\n"
        "                            continue\n"
        "                        bn, pk = m2.group(1), m2.group(2)\n"
        "                        arm_obj = pid if getattr(pid, 'pose', None) else None\n"
        "                        if not arm_obj and getattr(pid, 'bones', None):\n"
        "                            for o in bpy.data.objects:\n"
        "                                if o.type == 'ARMATURE' and getattr(o, 'data', None) == pid and getattr(o, 'pose', None):\n"
        "                                    arm_obj = o\n"
        "                                    break\n"
        "                        if arm_obj and bn in arm_obj.pose.bones and pk in arm_obj.pose.bones[bn]:\n"
        "                            var_val = 1 if arm_obj.pose.bones[bn][pk] else 0\n"
        "                            break\n"
        "                    except Exception:\n"
        "                        pass\n"
        "                if var_val is None:\n"
        "                    continue\n"
        "                expr = (getattr(dr, 'expression', None) or '').strip()\n"
        "                # prop=0 -> hide this mesh, prop=1 -> show (e.g. Jacket=0 hides jacket only).\n"
        "                if '1-' in expr.replace(' ', '') or '1 -' in expr or ('not ' in expr and 'var' in expr):\n"
        "                    hide_val = 1 if var_val else 0\n"
        "                else:\n"
        "                    hide_val = 0 if var_val else 1\n"
        "                try:\n"
        "                    if dp == 'hide_viewport':\n"
        "                        mesh_obj.hide_viewport = bool(hide_val)\n"
        "                        mesh_obj.hide_render = bool(hide_val)\n"
        "                    else:\n"
        "                        mesh_obj.hide_render = bool(hide_val)\n"
        "                        mesh_obj.hide_viewport = bool(hide_val)\n"
        "                except Exception:\n"
        "                    pass\n"
        "        # Object-level fallback by name (meshes named leg/boot etc.); respect boots_on.\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type != 'MESH':\n"
        "                continue\n"
        "            name = (obj.name or '').lower()\n"
        "            if boots_on:\n"
        "                if 'boot' in name or 'shoe' in name or 'foot' in name:\n"
        "                    obj.hide_set(False)\n"
        "                    obj.hide_viewport = False\n"
        "                if ('leg' in name or 'calf' in name or 'shin' in name) and 'boot' not in name and 'shoe' not in name:\n"
        "                    obj.hide_set(True)\n"
        "                    obj.hide_viewport = True\n"
        "            else:\n"
        "                if 'boot' in name or 'shoe' in name or 'foot' in name:\n"
        "                    obj.hide_set(True)\n"
        "                    obj.hide_viewport = True\n"
        "                if ('leg' in name or 'calf' in name or 'shin' in name) and 'boot' not in name and 'shoe' not in name:\n"
        "                    obj.hide_set(False)\n"
        "                    obj.hide_viewport = False\n"
        "    # Force depsgraph to re-evaluate so glTF export sees our modifier/bone visibility.\n"
        "    try:\n"
        "        bpy.context.view_layer.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "    try:\n"
        "        dg2 = bpy.context.evaluated_depsgraph_get()\n"
        "        if dg2:\n"
        "            dg2.update()\n"
        "    except Exception:\n"
        "        pass\n"
        "    print('[BlendExport] Applied visibility driver defaults (Boots=1 etc.)')\n"
        "\n"
        "def get_props_bone_name():\n"
        "    for arm in bpy.data.armatures:\n"
        "        if 'Properties' in arm.bones:\n"
        "            return 'Properties'\n"
        "    if getattr(bpy.types, 'BoneCollection', None):\n"
        "        for arm in bpy.data.armatures:\n"
        "            for coll in getattr(arm, 'collections_all', []) or []:\n"
        "                if getattr(coll, 'name', None) == 'Properties' and getattr(coll, 'bones', None):\n"
        "                    for b in coll.bones:\n"
        "                        if b and getattr(b, 'name', None):\n"
        "                            return b.name\n"
        "                    break\n"
        "    return None\n"
        "\n"
        "def build_property_material_map(props_bone_name, out_path):\n"
        "    import re\n"
        "    import os\n"
        "    prop_to_materials = {}\n"
        "    prop_to_objects = {}\n"
        "    prop_to_images = {}\n"
        "    def prop_from_target_datapath(tdp):\n"
        "        if not tdp:\n"
        "            return None\n"
        "        m = re.search(r\"pose\\.bones\\[['\\\"]([^'\\\"]+)['\\\"]\\]\\[['\\\"]([^'\\\"]+)['\\\"]\\]\", tdp)\n"
        "        if m and m.group(1) == props_bone_name:\n"
        "            return m.group(2)\n"
        "        m = re.search(r\"bones\\[['\\\"]([^'\\\"]+)['\\\"]\\]\\[['\\\"]([^'\\\"]+)['\\\"]\\]\", tdp)\n"
        "        if m and m.group(1) == props_bone_name:\n"
        "            return m.group(2)\n"
        "        return None\n"
        "    def _norm_filename(s):\n"
        "        s = (s or '').strip()\n"
        "        if not s:\n"
        "            return ''\n"
        "        s = os.path.basename(s)\n"
        "        s = re.sub(r'\\.\\d{3}$', '', s)\n"
        "        return s\n"
        "    def image_basenames_for_material(m):\n"
        "        out = set()\n"
        "        if not m or not getattr(m, 'use_nodes', False) or not getattr(m, 'node_tree', None):\n"
        "            return out\n"
        "        for n in m.node_tree.nodes:\n"
        "            if getattr(n, 'type', None) != 'TEX_IMAGE':\n"
        "                continue\n"
        "            img = getattr(n, 'image', None)\n"
        "            if not img:\n"
        "                continue\n"
        "            p = (getattr(img, 'filepath_raw', None) or getattr(img, 'filepath', None) or '').strip()\n"
        "            if not p:\n"
        "                continue\n"
        "            p = bpy.path.abspath(p)\n"
        "            b = _norm_filename(p)\n"
        "            if b:\n"
        "                out.add(b)\n"
        "        return out\n"
        "    for mat in bpy.data.materials:\n"
        "        if not mat or not getattr(mat, 'use_nodes', False) or not getattr(mat, 'node_tree', None):\n"
        "            continue\n"
        "        anim = getattr(mat.node_tree, 'animation_data', None)\n"
        "        if not anim or not getattr(anim, 'drivers', None):\n"
        "            continue\n"
        "        for fc in anim.drivers:\n"
        "            dr = getattr(fc, 'driver', None)\n"
        "            if not dr or not getattr(dr, 'variables', None):\n"
        "                continue\n"
        "            prop_key = None\n"
        "            for v in dr.variables:\n"
        "                for t in getattr(v, 'targets', []) or []:\n"
        "                    pk = prop_from_target_datapath(getattr(t, 'data_path', '') or '')\n"
        "                    if pk:\n"
        "                        prop_key = pk\n"
        "                        break\n"
        "                if prop_key:\n"
        "                    break\n"
        "            if not prop_key:\n"
        "                continue\n"
        "            prop_to_materials.setdefault(prop_key, set()).add(mat.name)\n"
        "            for bn in image_basenames_for_material(mat):\n"
        "                prop_to_images.setdefault(prop_key, set()).add(bn)\n"
        "    if prop_to_materials:\n"
        "        mats_of_interest = set()\n"
        "        for s in prop_to_materials.values():\n"
        "            mats_of_interest |= s\n"
        "        for obj in bpy.data.objects:\n"
        "            if not obj or obj.type != 'MESH':\n"
        "                continue\n"
        "            try:\n"
        "                for slot in obj.material_slots:\n"
        "                    m = getattr(slot, 'material', None)\n"
        "                    if m and m.name in mats_of_interest:\n"
        "                        for prop_key, mats in prop_to_materials.items():\n"
        "                            if m.name in mats:\n"
        "                                prop_to_objects.setdefault(prop_key, set()).add(obj.name)\n"
        "            except Exception:\n"
        "                pass\n"
        "    out = {}\n"
        "    for prop_key in prop_to_materials.keys():\n"
        "        imgs = [x for x in prop_to_images.get(prop_key, set()) if x]\n"
        "        out[prop_key] = {\n"
        "            'materials': sorted(list(prop_to_materials.get(prop_key, set()))),\n"
        "            'objects': sorted(list(prop_to_objects.get(prop_key, set()))),\n"
        "            'images': sorted(imgs)\n"
        "        }\n"
        "    with open(out_path, 'w', encoding='utf-8') as f:\n"
        "        json.dump(out, f, indent=None)\n"
        "    print('[BlendExport] Wrote property->materials map:', len(out), 'to', out_path)\n"
        "\n"
        "apply_visibility_driver_defaults(overrides)\n"
        "props_bone_for_matmap = get_props_bone_name()\n"
        "if props_bone_for_matmap and visibility_map_path:\n"
        "    try:\n"
        "        matmap_path = visibility_map_path.replace('_visibility.json', '_matmap.json')\n"
        "        build_property_material_map(props_bone_for_matmap, matmap_path)\n"
        "    except Exception as e:\n"
        "        print('[BlendExport] Property material map (non-fatal):', e)\n"
        "# Export pose at frame 0 (not rest/T-pose) so the character keeps its pose without animation.\n"
        "try:\n"
        "    bpy.context.scene.frame_set(0)\n"
        "except Exception:\n"
        "    pass\n"
        "\n"
        "errors = []\n"
        "ok = False\n"
        "glb_ok = False\n"
        "obj_ok = False\n"
        "try:\n"
        "    gltf_export_with_fallback(out_glb)\n"
        "    glb_ok = os.path.exists(out_glb)\n"
        "    print('[BlendExport] GLB export success:', glb_ok)\n"
        "except Exception as e:\n"
        "    print('[BlendExport] GLB export error:', str(e))\n"
        "    errors.append('GLB export: ' + str(e))\n"
        "\n"
        "parts_manifest = {}\n"
        "split_visibility_map = {}\n"
        "if glb_ok and visibility_map_path and os.path.isfile(visibility_map_path):\n"
        "    try:\n"
        "        with open(visibility_map_path, 'r', encoding='utf-8') as f:\n"
        "            split_visibility_map = json.load(f)\n"
        "    except Exception:\n"
        "        pass\n"
        "if glb_ok and split_visibility_map:\n"
        "    try:\n"
        "        togglable_mesh_names = set()\n"
        "        for v in split_visibility_map.values():\n"
        "            togglable_mesh_names.update(v or [])\n"
        "        base_mesh_names = set()\n"
        "        for obj in bpy.data.objects:\n"
        "            if obj.type == 'MESH' and (obj.name or '') not in togglable_mesh_names:\n"
        "                base_mesh_names.add(obj.name or '')\n"
        "        # Body = base meshes that are not head/face/plane (body only in part GLBs).\n"
        "        body_mesh_names = set()\n"
        "        for n in base_mesh_names:\n"
        "            if not n:\n"
        "                continue\n"
        "            low = n.lower()\n"
        "            if 'head' not in low and 'faceacc' not in low and 'plane' not in low:\n"
        "                body_mesh_names.add(n)\n"
        "        glb_dir = os.path.dirname(out_glb)\n"
        "        base_name = os.path.splitext(os.path.basename(out_glb))[0]\n"
        "        stem = re.sub(r'_opts_[a-f0-9]+$', '', base_name)\n"
        "        def sanitize_part(s):\n"
        "            return (re.sub(r'[^A-Za-z0-9_-]', '_', (s or '').strip()).strip('_') or 'part')\n"
        "        reload_images_for_export()\n"
        "        select_exportables_for_base(togglable_mesh_names, body_mesh_names)\n"
        "        base_glb = os.path.join(glb_dir, stem + '_base.glb')\n"
        "        gltf_export_with_fallback(base_glb)\n"
        "        parts_manifest['base'] = os.path.basename(base_glb)\n"
        "        parts_manifest['parts'] = {}\n"
        "        for prop_name, mesh_list in split_visibility_map.items():\n"
        "            if not mesh_list:\n"
        "                continue\n"
        "            part_set = set(mesh_list)\n"
        "            select_exportables_for_part(part_set, base_mesh_names)\n"
        "            part_fn = stem + '_part_' + sanitize_part(prop_name) + '.glb'\n"
        "            part_path = os.path.join(glb_dir, part_fn)\n"
        "            gltf_export_with_fallback(part_path)\n"
        "            parts_manifest['parts'][prop_name] = part_fn\n"
        "        parts_manifest['baseMeshNames'] = list(base_mesh_names - body_mesh_names)\n"
        "        parts_manifest['bodyMeshNames'] = list(body_mesh_names)\n"
        "        # Export skin mesh GLB (body + armature only) for CustomMaterial replacement at runtime.\n"
        "        def select_exportables_for_skin_mesh(body_mesh_names):\n"
        "            for obj in bpy.data.objects:\n"
        "                obj.select_set(False)\n"
        "            for obj in bpy.data.objects:\n"
        "                if obj.type == 'ARMATURE':\n"
        "                    obj.select_set(True)\n"
        "                elif obj.type == 'MESH' and (obj.name or '') in body_mesh_names:\n"
        "                    obj.select_set(True)\n"
        "        if body_mesh_names:\n"
        "            select_exportables_for_skin_mesh(body_mesh_names)\n"
        "            skin_glb = os.path.join(glb_dir, stem + '_skin_mesh.glb')\n"
        "            gltf_export_with_fallback(skin_glb)\n"
        "            parts_manifest['skinMesh'] = os.path.basename(skin_glb)\n"
        "        # Build custom_materials.json: skin/clothes texture basenames per variant for CustomMaterial (mix + u_roughness).\n"
        "        def build_custom_materials_json(props_bone_name, body_mesh_names, matmap, out_path):\n"
        "            def _norm(s):\n"
        "                s = (s or '').strip().replace('\\\\', '/')\n"
        "                return s.split('/')[-1].rsplit('.', 1)[0] if s else ''\n"
        "            def img_basenames(m):\n"
        "                out = set()\n"
        "                if not m or not getattr(m, 'node_tree', None):\n"
        "                    return out\n"
        "                for n in (m.node_tree.nodes or []):\n"
        "                    if getattr(n, 'type', None) != 'TEX_IMAGE' or not getattr(n, 'image', None):\n"
        "                        continue\n"
        "                    path = getattr(n.image, 'filepath_from_user', None) or getattr(n.image, 'filepath', None) or ''\n"
        "                    path = bpy.path.abspath(path) if path else ''\n"
        "                    bn = _norm(path)\n"
        "                    if bn:\n"
        "                        out.add(bn)\n"
        "                return out\n"
        "            if not props_bone_name or not matmap:\n"
        "                return\n"
        "            skin_roughness_mats = set((matmap.get('Skin Roughness') or {}).get('materials') or [])\n"
        "            color_prop = None\n"
        "            for k in ('Color Yellow/Black', 'Color Yellow Black', 'Color'):\n"
        "                if k in matmap:\n"
        "                    color_prop = k\n"
        "                    break\n"
        "            skin_variant0 = set()\n"
        "            skin_variant1 = set()\n"
        "            for arm_obj in bpy.data.objects:\n"
        "                if arm_obj.type != 'ARMATURE' or not arm_obj.data or props_bone_name not in arm_obj.pose.bones:\n"
        "                    continue\n"
        "                pb = arm_obj.pose.bones[props_bone_name]\n"
        "                if color_prop and color_prop in pb:\n"
        "                    try:\n"
        "                        orig = pb[color_prop]\n"
        "                        pb[color_prop] = 0.0\n"
        "                        bpy.context.view_layer.update()\n"
        "                        for mat in bpy.data.materials:\n"
        "                            if mat and mat.name in skin_roughness_mats:\n"
        "                                skin_variant0 |= img_basenames(mat)\n"
        "                        pb[color_prop] = 1.0\n"
        "                        bpy.context.view_layer.update()\n"
        "                        for mat in bpy.data.materials:\n"
        "                            if mat and mat.name in skin_roughness_mats:\n"
        "                                skin_variant1 |= img_basenames(mat)\n"
        "                        pb[color_prop] = orig\n"
        "                    except Exception:\n"
        "                        pass\n"
        "                    break\n"
        "            if not skin_variant0 and skin_roughness_mats:\n"
        "                for mat in bpy.data.materials:\n"
        "                    if mat and mat.name in skin_roughness_mats:\n"
        "                        skin_variant0 |= img_basenames(mat)\n"
        "            custom = {\n"
        "                'skin': {\n"
        "                    'baseColorVariant0': sorted([x for x in skin_variant0 if x]),\n"
        "                    'baseColorVariant1': sorted([x for x in skin_variant1 if x]) or sorted([x for x in skin_variant0 if x]),\n"
        "                    'roughnessMap': []\n"
        "                },\n"
        "                'clothes': { 'baseColorVariant0': [], 'baseColorVariant1': [], 'roughnessMap': [] }\n"
        "            }\n"
        "            with open(out_path, 'w', encoding='utf-8') as f:\n"
        "                json.dump(custom, f, indent=2)\n"
        "            print('[BlendExport] Wrote custom_materials.json')\n"
        "        custom_mat_path = os.path.join(glb_dir, stem + '_custom_materials.json')\n"
        "        matmap_path_here = visibility_map_path.replace('_visibility.json', '_matmap.json')\n"
        "        try:\n"
        "            with open(matmap_path_here, 'r', encoding='utf-8') as f:\n"
        "                matmap_data = json.load(f)\n"
        "        except Exception:\n"
        "            matmap_data = {}\n"
        "        if props_bone_for_matmap and body_mesh_names and matmap_data:\n"
        "            try:\n"
        "                build_custom_materials_json(props_bone_for_matmap, body_mesh_names, matmap_data, custom_mat_path)\n"
        "            except Exception as e:\n"
        "                print('[BlendExport] custom_materials (non-fatal):', e)\n"
        "        parts_json_path = os.path.join(glb_dir, stem + '_parts.json')\n"
        "        with open(parts_json_path, 'w', encoding='utf-8') as f:\n"
        "            json.dump(parts_manifest, f, indent=None)\n"
        "        print('[BlendExport] Split export: base +', len(parts_manifest.get('parts', {})), 'parts ->', parts_json_path)\n"
        "    except Exception as e:\n"
        "        print('[BlendExport] Split export (non-fatal):', e)\n"
        "        parts_manifest = {}\n"
        "\n"
        "# Fallback OBJ pass only if GLB failed.\n"
        "if not glb_ok:\n"
        "    try:\n"
        "        if hasattr(bpy.ops, 'wm') and hasattr(bpy.ops.wm, 'obj_export'):\n"
        "            try:\n"
        "                bpy.ops.wm.obj_export(\n"
        "                    filepath=out_obj,\n"
        "                    export_selected_objects=True,\n"
        "                    export_materials=True,\n"
        "                    path_mode='COPY'\n"
        "                )\n"
        "            except Exception:\n"
        "                bpy.ops.wm.obj_export(\n"
        "                    filepath=out_obj,\n"
        "                    export_selected_objects=True,\n"
        "                    export_materials=True\n"
        "                )\n"
        "        else:\n"
        "            try:\n"
        "                bpy.ops.export_scene.obj(\n"
        "                    filepath=out_obj,\n"
        "                    use_selection=True,\n"
        "                    use_materials=True,\n"
        "                    axis_forward='-Z',\n"
        "                    axis_up='Y',\n"
        "                    path_mode='COPY'\n"
        "                )\n"
        "            except Exception:\n"
        "                bpy.ops.export_scene.obj(\n"
        "                    filepath=out_obj,\n"
        "                    use_selection=True,\n"
        "                    use_materials=True,\n"
        "                    axis_forward='-Z',\n"
        "                    axis_up='Y'\n"
        "                )\n"
        "        obj_ok = os.path.exists(out_obj)\n"
        "        print('[BlendExport] OBJ export success:', obj_ok)\n"
        "    except Exception as e:\n"
        "        print('[BlendExport] OBJ export error:', str(e))\n"
        "        errors.append('OBJ fallback export: ' + str(e))\n"
        "    if obj_ok:\n"
        "        try:\n"
        "            rewrite_mtl_texture_paths(out_obj)\n"
        "        except Exception as e:\n"
        "            errors.append('MTL rewrite: ' + str(e))\n"
        "\n"
        "ok = glb_ok or obj_ok\n"
        "print('[BlendExport] Final status - glb_ok:', glb_ok, 'obj_ok:', obj_ok)\n"
        "if not ok:\n"
        "    raise RuntimeError(' | '.join(errors) if errors else 'Export failed')\n"
    );
    scriptFile.write(script);
    scriptFile.flush();

    const QString propsPath = propsPathForBlend(blendPath);
    QStringList processArgs = {
        "--background",
        blendPath,
        "--python",
        scriptFile.fileName(),
        "--",
        blendPath,
        outPath,
        outObjPath
    };
    QTemporaryFile overridesFile(QDir(ensureCacheDir()).absoluteFilePath("blend_overrides_XXXXXX.json"));
    if (!propertyOverrides.isEmpty()) {
        overridesFile.setAutoRemove(true);
        if (overridesFile.open()) {
            QJsonObject root;
            for (auto it = propertyOverrides.constBegin(); it != propertyOverrides.constEnd(); ++it) {
                const QVariant &v = it.value();
                if (v.canConvert<int>())
                    root.insert(it.key(), v.toInt());
                else if (v.canConvert<double>())
                    root.insert(it.key(), v.toDouble());
                else if (v.canConvert<QString>())
                    root.insert(it.key(), v.toString());
            }
            overridesFile.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
            overridesFile.close();
            processArgs.append(overridesFile.fileName());
        } else {
            processArgs.append(QString());
        }
    } else {
        processArgs.append(QString());
    }
    processArgs.append(propsPath);
    processArgs.append(visibilityMapPathForBlend(blendPath));

    QProcess process;
    process.setProgram(blenderExe);
    process.setArguments(processArgs);
    process.start();
    if (!process.waitForStarted(10000)) {
        if (errorOut)
            *errorOut = tr("Failed to start Blender process.");
        return QString();
    }
    process.waitForFinished(-1);
    const QString processOut = QString::fromUtf8(process.readAllStandardOutput());
    const QString processErr = QString::fromUtf8(process.readAllStandardError());
    if (!processOut.trimmed().isEmpty()) {
        qInfo().noquote() << "[ModelSourceResolver] Blender stdout:\n" + processOut.trimmed();
    }
    if (!processErr.trimmed().isEmpty()) {
        qWarning().noquote() << "[ModelSourceResolver] Blender stderr:\n" + processErr.trimmed();
    }
    const int missingTextureCount = processOut.count("Could not find '");
    if (missingTextureCount > 0) {
        qWarning() << "[ModelSourceResolver] Missing texture references detected during export:" << missingTextureCount;
        qWarning() << "[ModelSourceResolver] Model may render with fallback materials where files are unavailable.";
    }

    const bool objExists = QFileInfo::exists(outObjPath);
    const bool glbExists = QFileInfo::exists(outPath);
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 || (!glbExists && !objExists)) {
        QString details = processErr.trimmed();
        if (details.isEmpty())
            details = processOut.trimmed();
        if (details.length() > 300)
            details = details.left(300) + "...";
        if (errorOut)
            *errorOut = tr("Blend conversion failed via Blender CLI.") + (details.isEmpty() ? QString() : " " + details);
        qWarning() << "[ModelSourceResolver] Blend conversion failed for" << blendPath;
        return QString();
    }

    // Prefer GLB for native Blender features: lights, cameras, armatures, animations, morphs.
    if (glbExists) {
        const QDir outDir = QFileInfo(outPath).absolutePath();
        QString stem = QFileInfo(outPath).completeBaseName();
        stem.replace(QRegularExpression(QLatin1String("_opts_[a-f0-9]+$")), QString());
        const QString partsJsonPath = outDir.absoluteFilePath(stem + QLatin1String("_parts.json"));
        if (QFileInfo::exists(partsJsonPath)) {
            QFile pf(partsJsonPath);
            if (pf.open(QIODevice::ReadOnly | QIODevice::Text)) {
                const QJsonDocument pd = QJsonDocument::fromJson(pf.readAll());
                pf.close();
                const QString baseFn = pd.object().value(QLatin1String("base")).toString();
                if (!baseFn.isEmpty()) {
                    const QString basePath = outDir.absoluteFilePath(baseFn);
                    if (QFileInfo::exists(basePath)) {
                        qInfo() << "[ModelSourceResolver] Conversion complete. Using split base GLB:" << basePath;
                        return basePath;
                    }
                }
            }
        }
        qInfo() << "[ModelSourceResolver] Conversion complete. Using GLB:" << outPath;
        return outPath;
    }
    if (objExists) {
        qInfo() << "[ModelSourceResolver] GLB missing, using OBJ fallback:" << outObjPath;
        normalizeObjMtlTexturePaths(outObjPath);
        return outObjPath;
    }
    qWarning() << "[ModelSourceResolver] Conversion reported success but no output found.";
    return outPath;
}
