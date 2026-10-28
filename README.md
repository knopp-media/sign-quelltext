# Knopp Media Sign – Quelltext der Änderungen an DocuSeal

Die Unterschriftsplattformen **sign.knopp-media.de** (Knopp Media GmbH) und **sign.pressekreis.de** (PresseKreis) beruhen auf [DocuSeal](https://github.com/docusealco/docuseal) in der Version **3.3.3**. DocuSeal steht unter der **GNU Affero General Public License v3.0** (siehe `LICENSE`).

Gemäß AGPL-3.0 stellen wir hier den Quelltext unserer Änderungen bereit. Geändert sind ausschließlich Darstellungsbausteine (Logo, Seitentitel, Link-Vorschau, Fußzeile von Seiten und E-Mails). Die Programmlogik von DocuSeal ist unverändert.

| Datei | Änderung |
|---|---|
| `views/shared/_logo.html.erb` | Markensymbol statt DocuSeal-Logo |
| `views/shared/_title.html.erb` | Markenlogo in der Kopfzeile der Verwaltung |
| `views/submit_form/_docuseal_logo.html.erb`, `views/start_form/_docuseal_logo.html.erb` | Markenlogo über den Formularen |
| `views/shared/_powered_by.html.erb`, `views/shared/_attribution.html.erb` | Fußzeile mit Marke und Link auf diesen Quelltext |
| `views/shared/_email_attribution.html.erb` | E-Mail-Fußzeile mit der Marke |
| `views/layouts/_head_tags.html.erb`, `views/shared/_html_title.html.erb`, `views/shared/_meta.html.erb` | Seitentitel, Link-Vorschau und Symbole mit der Marke |

Die Dateien ersetzen beim Start die gleichnamigen Dateien unter `/app/app/views/` im offiziellen Image `docuseal/docuseal:3.3.3`. Die Marke kommt aus der Umgebungsvariable `SIGN_MARKE`, die Bilder liegen unter `/app/public/branding/`. Den vollständigen Quelltext von DocuSeal finden Sie unter https://github.com/docusealco/docuseal.

Kontakt: Knopp Media GmbH, Oberlandstr. 26, 82335 Berg, info@knopp-media.de
