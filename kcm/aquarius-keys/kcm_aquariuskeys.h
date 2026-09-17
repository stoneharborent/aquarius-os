/*
    "Mac or Windows" — the AquariusOS page in KDE's System Settings.

    SPDX-FileCopyrightText: 2026 Stone Harbor Entertainment
    SPDX-License-Identifier: GPL-2.0-or-later

    ---------------------------------------------------------------------------
    WHAT THIS CLASS IS, IN PLAIN LANGUAGE
    ---------------------------------------------------------------------------
    System Settings does not know anything about keyboards. It loads this
    plugin, this plugin hands it a page (the QML file in ui/), and the page
    talks back to this class through an object it can see called "kcm".

    This class does exactly two things, and deliberately no more:

      mode()             reads ~/.config/aquarius/keys.conf and says "mac" or
                         "windows". A missing file means "mac", because that is
                         the AquariusOS default.
      choose("mac")      runs `aq keys mac` and nothing else.

    ⚠️ IT NEVER WRITES THE SETTINGS FILE ITSELF. /usr/bin/aq owns that file, and
    changing the mode is two jobs, not one: write the file, and restart the
    remapper so the new shortcuts are live without logging out. Writing the file
    here would do half of it and look broken.

    ⚠️ THE KEYBOARD ONLY, SINCE 2026-09-17. This page used to change where the
    window buttons sat too. Royce dropped that, because applications that draw
    their own title bar never followed it.
*/

#pragma once

#include <KQuickConfigModule>

#include <QProcess>
#include <QString>

class AquariusKeysKcm : public KQuickConfigModule
{
    Q_OBJECT

    /*! Which style is switched on right now: "mac" or "windows". */
    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)

    /*! True while `aq keys ...` is still running, so the page can go quiet. */
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

    /*! Empty unless the last attempt failed; then it is a sentence to show. */
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

public:
    explicit AquariusKeysKcm(QObject *parent, const KPluginMetaData &metaData);
    ~AquariusKeysKcm() override;

    QString mode() const;
    bool busy() const;
    QString errorMessage() const;

    /*!
     * Switch to "mac" or "windows" by running /usr/bin/aq.
     *
     * Runs in the background: System Settings keeps drawing while it works.
     */
    Q_INVOKABLE void choose(const QString &mode);

    /*! Re-read the settings file. Called when the page becomes visible. */
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void modeChanged();
    void busyChanged();
    void errorMessageChanged();

private:
    void setErrorMessage(const QString &message);

    QString m_mode;
    QString m_errorMessage;
    QProcess *m_process = nullptr;
};
