/*
    "Mac or Windows" — the AquariusOS page in KDE's System Settings.

    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later

    Read kcm_aquariuskeys.h first: it explains what this class is for and what
    it deliberately does not do.
*/

#include "kcm_aquariuskeys.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>

// The command that owns this setting. Absolute, not looked up on the PATH: a
// settings page must not depend on what happens to be in somebody's PATH.
static const QString AQ_COMMAND = QStringLiteral("/usr/bin/aq");

// ⚠️ THE DEFAULT IS MAC, AND THAT RULE IS WRITTEN IN FOUR PLACES — here,
// /usr/bin/aq, /usr/libexec/aquarius-keys-run, and the GNOME quick-settings
// add-on. All four must agree, or the computer disagrees with itself about
// what it is.
static const QString DEFAULT_MODE = QStringLiteral("mac");

/*!
 * Where the answer lives: ~/.config/aquarius/keys.conf.
 *
 * QStandardPaths::ConfigLocation is the same folder `aq` means by
 * ${XDG_CONFIG_HOME:-$HOME/.config}.
 */
static QString keysConfPath()
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    return base + QStringLiteral("/aquarius/keys.conf");
}

/*!
 * Read the mode out of that file.
 *
 * The file is a few lines of comment and one `mode=` line. The LAST mode= line
 * wins, which is what `aq` does too — a file somebody has half-edited by hand
 * can have two of them, and the two programs have to agree on which one counts.
 *
 * Anything unexpected — no file, no permission, a word nobody recognises —
 * means Mac.
 */
static QString readMode()
{
    QFile file(keysConfPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        // No file yet is the normal case on a fresh account, not a fault.
        return DEFAULT_MODE;
    }

    static const QRegularExpression modeLine(QStringLiteral("^\\s*mode\\s*=\\s*([A-Za-z]+)"));

    QString found = DEFAULT_MODE;
    QTextStream stream(&file);
    while (!stream.atEnd()) {
        const QRegularExpressionMatch match = modeLine.match(stream.readLine());
        if (!match.hasMatch()) {
            continue;
        }
        const QString word = match.captured(1);
        if (word == QLatin1String("mac") || word == QLatin1String("windows")) {
            found = word;
        }
    }
    return found;
}

AquariusKeysKcm::AquariusKeysKcm(QObject *parent, const KPluginMetaData &metaData)
    : KQuickConfigModule(parent, metaData)
    , m_mode(readMode())
{
}

AquariusKeysKcm::~AquariusKeysKcm() = default;

QString AquariusKeysKcm::mode() const
{
    return m_mode;
}

bool AquariusKeysKcm::busy() const
{
    return m_process != nullptr;
}

QString AquariusKeysKcm::errorMessage() const
{
    return m_errorMessage;
}

void AquariusKeysKcm::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message) {
        return;
    }
    m_errorMessage = message;
    Q_EMIT errorMessageChanged();
}

void AquariusKeysKcm::refresh()
{
    const QString current = readMode();
    if (current == m_mode) {
        return;
    }
    m_mode = current;
    Q_EMIT modeChanged();
}

void AquariusKeysKcm::choose(const QString &mode)
{
    // Only two answers are possible. Anything else is a bug in the page, and
    // the right response is to do nothing rather than run a strange command.
    if (mode != QLatin1String("mac") && mode != QLatin1String("windows")) {
        return;
    }

    // Already there. Running the command anyway would restart the key remapper
    // for no reason.
    if (mode == m_mode) {
        return;
    }

    // One at a time. Two overlapping `aq keys` runs would race each other to
    // write the same file.
    if (m_process) {
        return;
    }

    setErrorMessage(QString());

    // ⚠️ RUN IT IN THE BACKGROUND. Waiting for a command to finish inside a
    // settings page freezes the whole window while it works — and this command
    // restarts a service, which is not instant.
    m_process = new QProcess(this);
    m_process->setProgram(AQ_COMMAND);
    m_process->setArguments({QStringLiteral("keys"), mode});
    m_process->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_process, &QProcess::finished, this, [this, mode](int exitCode, QProcess::ExitStatus status) {
        const QString output = QString::fromUtf8(m_process->readAll()).trimmed();

        if (status != QProcess::NormalExit || exitCode != 0) {
            setErrorMessage(output.isEmpty()
                                ? i18n("The keyboard style could not be changed.")
                                : output);
        }

        m_process->deleteLater();
        m_process = nullptr;
        Q_EMIT busyChanged();

        // Read the file back rather than assuming the command did what it said.
        // Trust content, never intentions.
        refresh();
    });

    // ⚠️ A COMMAND THAT NEVER STARTS NEVER "FINISHES" EITHER. If /usr/bin/aq is
    // missing, Qt reports FailedToStart and the handler above is never called —
    // so without this the page would sit saying "working..." forever. Clean up
    // here as well, and only here, because every other error is followed by
    // finished() in the usual way.
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) {
            return;
        }
        setErrorMessage(i18n("AquariusOS could not run %1. This copy of the system is incomplete.", AQ_COMMAND));
        m_process->deleteLater();
        m_process = nullptr;
        Q_EMIT busyChanged();
    });

    m_process->start();
    Q_EMIT busyChanged();
}

K_PLUGIN_CLASS_WITH_JSON(AquariusKeysKcm, "kcm_aquariuskeys.json")

#include "kcm_aquariuskeys.moc"
