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

namespace {
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

    watcher->setFuture(QtConcurrent::run([sourceUrl]() -> QPair<QUrl, QString> {
        QString error;
        const QUrl resolved = ModelSourceResolver::resolveForViewingInternal(sourceUrl, &error);
        return qMakePair(resolved, error);
    }));
}

QUrl ModelSourceResolver::resolveForViewingInternal(const QUrl &sourceUrl, QString *errorOut)
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
        const QString glbPath = convertBlendToGlb(sourcePath, &convertError);
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
    QDir cacheDir(tempRoot + "/s3rp3nt_media_model_cache");
    if (!cacheDir.exists()) {
        cacheDir.mkpath(".");
    }
    return cacheDir.absolutePath();
}

QString ModelSourceResolver::cachePathForBlend(const QString &blendPath)
{
    const QFileInfo info(blendPath);
    const QByteArray hashBytes = QCryptographicHash::hash(blendPath.toUtf8(), QCryptographicHash::Sha1).toHex();
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
    const QString fileName = safeBase + "_" + hash + ".glb";
    return QDir(ensureCacheDir()).absoluteFilePath(fileName);
}

QString ModelSourceResolver::convertBlendToGlb(const QString &blendPath, QString *errorOut)
{
    const QString blenderExe = findBlenderExecutable();
    if (blenderExe.isEmpty()) {
        if (errorOut)
            *errorOut = tr("Blender executable not found. Install Blender or set BLENDER_EXECUTABLE.");
        return QString();
    }

    const QString outPath = cachePathForBlend(blendPath);
    const QString outObjPath = QFileInfo(outPath).absolutePath() + "/" + QFileInfo(outPath).completeBaseName() + ".obj";
    const QString outMtlPath = QFileInfo(outObjPath).absolutePath() + "/" + QFileInfo(outObjPath).completeBaseName() + ".mtl";
    const QFileInfo outInfo(outPath);
    const QFileInfo outObjInfo(outObjPath);
    const QFileInfo inInfo(blendPath);

    auto objMtlLooksPortable = [&outMtlPath]() -> bool {
        QFile mtlFile(outMtlPath);
        if (!mtlFile.exists() || !mtlFile.open(QIODevice::ReadOnly | QIODevice::Text))
            return false;
        QTextStream stream(&mtlFile);
        int scanned = 0;
        while (!stream.atEnd() && scanned < 4000) {
            const QString line = stream.readLine().trimmed();
            ++scanned;
            if (line.startsWith("map_", Qt::CaseInsensitive) || line.startsWith("bump ", Qt::CaseInsensitive)) {
                const QString lower = line.toLower();
                if (lower.contains(":/") || lower.startsWith("c:/") || lower.startsWith("d:/") || lower.startsWith("e:/")) {
                    return false;
                }
            }
        }
        return true;
    };

    if (outObjInfo.exists() && outObjInfo.lastModified() >= inInfo.lastModified() && objMtlLooksPortable()) {
        return outObjPath;
    }
    if (outInfo.exists() && outInfo.lastModified() >= inInfo.lastModified()) {
        // Old cache may only have GLB. Re-run conversion to generate OBJ+MTL second pass.
    }

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
        "import shutil\n"
        "import sys\n"
        "\n"
        "argv = sys.argv\n"
        "if '--' in argv:\n"
        "    argv = argv[argv.index('--') + 1:]\n"
        "if len(argv) < 3:\n"
        "    raise RuntimeError('Missing export arguments')\n"
        "blend_path, out_glb, out_obj = argv[0], argv[1], argv[2]\n"
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
        "# Improve texture reliability for converted scenes.\n"
        "try:\n"
        "    bpy.ops.file.find_missing_files(directory=os.path.dirname(blend_path))\n"
        "except Exception:\n"
        "    pass\n"
        "try:\n"
        "    bpy.ops.file.pack_all()\n"
        "except Exception:\n"
        "    pass\n"
        "\n"
        "def simplify_materials_for_export():\n"
        "    for mat in bpy.data.materials:\n"
        "        if mat is None:\n"
        "            continue\n"
        "        if not mat.use_nodes:\n"
        "            continue\n"
        "        nt = mat.node_tree\n"
        "        if nt is None:\n"
        "            continue\n"
        "        nodes = nt.nodes\n"
        "        links = nt.links\n"
        "        out = None\n"
        "        for n in nodes:\n"
        "            if n.type == 'OUTPUT_MATERIAL':\n"
        "                out = n\n"
        "                break\n"
        "        if out is None:\n"
        "            out = nodes.new('ShaderNodeOutputMaterial')\n"
        "\n"
        "        principled = None\n"
        "        for n in nodes:\n"
        "            if n.type == 'BSDF_PRINCIPLED':\n"
        "                principled = n\n"
        "                break\n"
        "        if principled is None:\n"
        "            principled = nodes.new('ShaderNodeBsdfPrincipled')\n"
        "\n"
        "        image_node = None\n"
        "        for n in nodes:\n"
        "            if n.type == 'TEX_IMAGE' and getattr(n, 'image', None) is not None:\n"
        "                image_node = n\n"
        "                break\n"
        "\n"
        "        if image_node is not None:\n"
        "            try:\n"
        "                links.new(image_node.outputs.get('Color'), principled.inputs.get('Base Color'))\n"
        "            except Exception:\n"
        "                pass\n"
        "            try:\n"
        "                links.new(image_node.outputs.get('Alpha'), principled.inputs.get('Alpha'))\n"
        "            except Exception:\n"
        "                pass\n"
        "\n"
        "        try:\n"
        "            links.new(principled.outputs.get('BSDF'), out.inputs.get('Surface'))\n"
        "        except Exception:\n"
        "            pass\n"
        "\n"
        "def select_exportables():\n"
        "    try:\n"
        "        if bpy.ops.object.mode_set.poll():\n"
        "            bpy.ops.object.mode_set(mode='OBJECT')\n"
        "    except Exception:\n"
        "        pass\n"
        "    for obj in bpy.data.objects:\n"
        "        obj.select_set(False)\n"
        "    export_types = {'MESH', 'CURVE', 'SURFACE', 'META', 'FONT'}\n"
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
        "    return len(selected) > 0\n"
        "\n"
        "simplify_materials_for_export()\n"
        "select_exportables()\n"
        "os.makedirs(os.path.dirname(out_glb), exist_ok=True)\n"
        "\n"
        "errors = []\n"
        "ok = False\n"
        "glb_ok = False\n"
        "obj_ok = False\n"
        "try:\n"
        "    bpy.ops.export_scene.gltf(\n"
        "        filepath=out_glb,\n"
        "        export_format='GLB',\n"
        "        use_selection=True,\n"
        "        export_apply=True,\n"
        "        export_texcoords=True,\n"
        "        export_normals=True,\n"
        "        export_tangents=True,\n"
        "        export_materials='EXPORT',\n"
        "        export_image_format='AUTO',\n"
        "        export_animations=True,\n"
        "        export_yup=True\n"
        "    )\n"
        "    glb_ok = os.path.exists(out_glb)\n"
        "except Exception as e:\n"
        "    errors.append('GLB export: ' + str(e))\n"
        "\n"
        "\n"
        "# Second pass: always try OBJ+MTL for better texture compatibility.\n"
        "try:\n"
        "    if hasattr(bpy.ops, 'wm') and hasattr(bpy.ops.wm, 'obj_export'):\n"
        "        try:\n"
        "            bpy.ops.wm.obj_export(\n"
        "                filepath=out_obj,\n"
        "                export_selected_objects=True,\n"
        "                export_materials=True,\n"
        "                path_mode='COPY'\n"
        "            )\n"
        "        except Exception:\n"
        "            bpy.ops.wm.obj_export(\n"
        "                filepath=out_obj,\n"
        "                export_selected_objects=True,\n"
        "                export_materials=True\n"
        "            )\n"
        "    else:\n"
        "        try:\n"
        "            bpy.ops.export_scene.obj(\n"
        "                filepath=out_obj,\n"
        "                use_selection=True,\n"
        "                use_materials=True,\n"
        "                axis_forward='-Z',\n"
        "                axis_up='Y',\n"
        "                path_mode='COPY'\n"
        "            )\n"
        "        except Exception:\n"
        "            bpy.ops.export_scene.obj(\n"
        "                filepath=out_obj,\n"
        "                use_selection=True,\n"
        "                use_materials=True,\n"
        "                axis_forward='-Z',\n"
        "                axis_up='Y'\n"
        "            )\n"
        "    obj_ok = os.path.exists(out_obj)\n"
        "except Exception as e:\n"
        "    errors.append('OBJ second pass export: ' + str(e))\n"
        "if obj_ok:\n"
        "    try:\n"
        "        rewrite_mtl_texture_paths(out_obj)\n"
        "    except Exception as e:\n"
        "        errors.append('MTL rewrite: ' + str(e))\n"
        "\n"
        "ok = glb_ok or obj_ok\n"
        "if not ok:\n"
        "    raise RuntimeError(' | '.join(errors) if errors else 'Export failed')\n"
    );
    scriptFile.write(script);
    scriptFile.flush();

    QProcess process;
    process.setProgram(blenderExe);
    process.setArguments({
        "--background",
        blendPath,
        "--python",
        scriptFile.fileName(),
        "--",
        blendPath,
        outPath,
        outObjPath
    });
    process.start();
    if (!process.waitForStarted(10000)) {
        if (errorOut)
            *errorOut = tr("Failed to start Blender process.");
        return QString();
    }
    process.waitForFinished(-1);

    const bool objExists = QFileInfo::exists(outObjPath);
    const bool glbExists = QFileInfo::exists(outPath);
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 || (!glbExists && !objExists)) {
        const QString err = QString::fromUtf8(process.readAllStandardError());
        const QString out = QString::fromUtf8(process.readAllStandardOutput());
        QString details = err.trimmed();
        if (details.isEmpty())
            details = out.trimmed();
        if (details.length() > 300)
            details = details.left(300) + "...";
        if (errorOut)
            *errorOut = tr("Blend conversion failed via Blender CLI.") + (details.isEmpty() ? QString() : " " + details);
        return QString();
    }

    // Prefer OBJ second pass for better texture reliability in current runtime loader.
    if (objExists) {
        normalizeObjMtlTexturePaths(outObjPath);
        return outObjPath;
    }
    return outPath;
}
