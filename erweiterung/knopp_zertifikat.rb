# frozen_string_literal: true

# Knopp Media Sign: eigenes Abschlusszertifikat statt des DocuSeal-Prüfprotokolls (angelehnt an das
# „Certificate of Signature“ von PandaDoc: Guilloche-Band wie auf Wertpapieren, Siegel, Spalten
# Unterzeichner | Zeitstempel | Unterschrift) und Marke statt „DocuSeal“ in Signatur, PDF-Metadaten und Mails.
# Eingebunden per Compose als config/initializers/knopp_zertifikat.rb. Ersetzt nur Methoden (prepend),
# DocuSeal-Dateien bleiben unverändert; branding/pruefen.sh hält das Ausrollen an, wenn sich die
# benutzten DocuSeal-Teile ändern (erweiterung/abhaengig.sha256).
module KnoppMarke
  NAME = ENV.fetch('SIGN_MARKE', 'Knopp Media')
  PK = NAME == 'PresseKreis'
  HOST = ENV.fetch('HOST', PK ? 'sign.pressekreis.de' : 'sign.knopp-media.de')
  FIRMA = PK ? 'PresseKreis · Ein Service der Knopp Media GmbH' : 'Knopp Media GmbH'
  FARBE = PK ? '020b23' : 'ff8a00'      # Hauptfarbe (Logo)
  AKZENT = PK ? 'd6a64d' : '222222'     # zweite Farbe (Goldkante bzw. Dunkelgrau)
  PAPIER = PK ? 'f7f5ef' : 'fbf7f1'     # Hintergrund des Zertifikats
  LOGO = '/app/public/branding/logo.png'
  ZEICHEN = '/app/public/branding/icon.png'
  LOGO_BREITE = PK ? 170 : 135          # Punkte, Höhe ergibt sich aus 120 px Bildhöhe

  module Produkt
    def product_name
      KnoppMarke::NAME
    end
  end

  module Signatur
    def sign_reason(name)
      "Elektronisch unterschrieben von #{name} über #{KnoppMarke::HOST}"
    end

    def single_sign_reason(submitter)
      signers = submitter.submission.submitters.reject(&:viewer?).sort_by(&:completed_at).map { |s| s.email || s.name || s.phone }
      sign_reason(signers.reverse.join(', '))
    end

    def info_creator
      "#{KnoppMarke::NAME} Sign (#{KnoppMarke::HOST})"
    end
  end

  module Zertifikat
    TEXT = '1f2433'
    GRAU = '6b7280'
    LINIE = 'd9dce3'
    EREIGNISSE = {
      'send_email' => 'Unterschriftslink per E-Mail gesendet an',
      'send_reminder_email' => 'Erinnerung per E-Mail gesendet an',
      'click_email' => 'E-Mail-Link geöffnet von',
      'view_form' => 'Dokument angesehen von',
      'start_form' => 'Ausfüllen begonnen von',
      'complete_form' => 'Unterschrieben von',
      'api_complete_form' => 'Ausgefüllt und abgeschlossen (ohne Unterschrift) von',
      'decline_form' => 'Abgelehnt von'
    }.freeze
    INTERN = /\A(10|127|172\.(1[6-9]|2\d|3[01])|192\.168)\./

    def sign_reason
      "Abschlusszertifikat #{KnoppMarke::NAME} (#{KnoppMarke::HOST})"
    end

    # rubocop:disable Metrics
    def build_audit_trail(submission)
      account = submission.account
      font = self::FONT_NAME
      composer = HexaPDF::Composer.new(skip_page_creation: true)
      if Docuseal.pdf_format == 'pdf/a-3b'
        composer.document.task(:pdfa, level: '3b')
      elsif font == 'GoNotoKurrent'
        composer.document.task(:pdfa)
      end
      composer.document.config['font.map'] = { 'Helvetica' => { none: self::FONT_PATH, bold: self::FONT_BOLD_PATH },
                                               font => { none: self::FONT_PATH, bold: self::FONT_BOLD_PATH } }
      composer.document.config['font.on_missing_glyph'] = Submissions::GenerateResultAttachments.method(:on_missing_glyph).to_proc

      timezone = account.timezone
      zeit = ->(t) { t && "#{t.in_time_zone(timezone).strftime('%d.%m.%Y  %H:%M:%S')} #{TimeUtils.timezone_abbr(timezone, t)}" }
      fett = ->(text, **o) { { text: text.to_s, font: [font, { variant: :bold }], **o } }
      marke = ->(text) { { text: "#{text}\n", font: [font, { variant: :bold }], font_size: 6, fill_color: GRAU, character_spacing: 0.9 } }
      wert = ->(text, **o) { { text: "#{text}\n", font_size: 8.5, character_spacing: 0.3, **o } }
      box = ->(teile, **o) { composer.document.layout.formatted_text_box(teile.compact, line_spacing: 1.3, **o) }

      referenz = Digest::MD5.hexdigest(submission.slug).upcase.scan(/.{4}/).first(5).join('-')
      titel = submission.name || submission.template&.name || 'Dokument'
      submitters = submission.template_submitters.filter_map { |i| [i, submission.submitters.find { |s| s.uuid == i['uuid'] }] }
                             .select { |_, s| s }
      abgeschlossen = submission.submitters.filter_map(&:completed_at).max
      seitenzahl = 0

      composer.page_style(:default, page_size: :A4) do |canvas, style|
        seitenzahl += 1
        hintergrund(canvas, erste: seitenzahl == 1)
        style.frame = style.create_frame(canvas.context, [78, 58, 64, 58])
      end
      composer.style(:base, font:, font_size: 8.5, fill_color: TEXT, line_spacing: 1.25)
      composer.style(:abschnitt, font: [font, { variant: :bold }], font_size: 7.5, fill_color: KnoppMarke::FARBE,
                                 character_spacing: 1.4, padding: [14, 0, 6, 0])
      composer.new_page

      # Kopf: Logo, Titel, Referenz und Abschluss
      composer.image(KnoppMarke::LOGO, width: KnoppMarke::LOGO_BREITE, style: { align: :center }) if File.exist?(KnoppMarke::LOGO)
      composer.formatted_text([fett.call('ABSCHLUSSZERTIFIKAT', font_size: 21, character_spacing: 2.2, fill_color: KnoppMarke::FARBE)],
                              text_align: :center, padding: [12, 0, 0, 0])
      composer.formatted_text([{ text: 'über die elektronische Unterschrift', font_size: 9.5, fill_color: GRAU }],
                              text_align: :center, padding: [0, 0, 14, 0])
      composer.table([[box.call([marke.call('REFERENZNUMMER'), wert.call(referenz), marke.call('DOKUMENT'), wert.call(titel)]),
                       box.call([marke.call('VON ALLEN PARTEIEN ABGESCHLOSSEN AM'),
                                 wert.call(zeit.call(abgeschlossen) || 'noch offen'),
                                 abgeschlossen && { text: "#{abgeschlossen.utc.strftime('%d.%m.%Y  %H:%M:%S')} UTC\n", font_size: 7, fill_color: GRAU }],
                                text_align: :right)]],
                     column_widths: [-1, -1], cell_style: { padding: [0, 0, 6, 0], border: { width: 0 } })

      # Unterzeichner | Zeitstempel | Unterschrift
      kopf = %w[UNTERZEICHNER ZEITSTEMPEL UNTERSCHRIFT].map do |t|
        box.call([fett.call(t, font_size: 7, character_spacing: 1.2, fill_color: KnoppMarke::FARBE)])
      end
      zeilen = submitters.map do |item, s|
        events = submission.submission_events.select { |e| e.submitter_id == s.id }
        erstes = ->(typ) { events.select { |e| e.event_type == typ }.min_by(&:event_timestamp) }
        fertig = erstes.call('complete_form')
        api = erstes.call('api_complete_form')
        gesendet = erstes.call('send_email')
        geklickt = events.select { |e| e.event_type.in?(%w[click_email email_verified]) }.min_by(&:event_timestamp)
        daten = fertig&.data || {}
        ip = daten['ip'].to_s.match?(INTERN) ? nil : daten['ip']

        person = [fett.call("#{(s.name.presence || s.email).to_s.upcase}\n", font_size: 9.5, character_spacing: 0.4),
                  { text: "#{item['name']}\n\n", font_size: 7.5, fill_color: GRAU },
                  marke.call('E-MAIL'), wert.call(s.email.to_s),
                  marke.call('EMPFÄNGERPRÜFUNG'),
                  wert.call(if api then 'Eigene Seite, über den Assistenten'
                            elsif geklickt then "Persönlicher E-Mail-Link geöffnet\n#{zeit.call(geklickt.event_timestamp)}"
                            elsif gesendet then 'Link per E-Mail zugestellt'
                            else 'Persönlicher Link (ohne E-Mail)'
                            end)]
        stempel = [['GESENDET', gesendet&.event_timestamp], ['ANGESEHEN', erstes.call('view_form')&.event_timestamp],
                   ['UNTERSCHRIEBEN', fertig&.event_timestamp], ['ABGESCHLOSSEN (OHNE UNTERSCHRIFT)', api&.event_timestamp]]
                  .select { |_, t| t }.flat_map { |k, t| [marke.call(k), wert.call(zeit.call(t))] }
        bild = unterschrift_bild(submission, s)
        unterschrift = []
        unterschrift << composer.document.layout.image_box(bild[:io], width: bild[:breite], height: bild[:hoehe],
                                                           style: { border: { width: 0.7, color: KnoppMarke::AKZENT }, padding: 5 }) if bild
        unterschrift << box.call([api ? { text: "keine Unterschrift nötig\n", fill_color: GRAU } : (bild ? nil : { text: "–\n", fill_color: GRAU }),
                                  ip && marke.call('IP-ADRESSE'), ip && wert.call(ip),
                                  daten['ua'] && marke.call('GERÄT'), daten['ua'] && wert.call(geraet(daten['ua'])),
                                  s.timezone && marke.call('ZEITZONE'), s.timezone && wert.call(s.timezone.to_s)], padding: [6, 0, 0, 0])
        [box.call(person), box.call(stempel.presence || [wert.call('noch offen', fill_color: GRAU)]),
         unterschrift]
      end
      composer.table(zeilen, header: ->(_t) { [kopf] }, column_widths: [-1.15, -1, -1.25],
                             cell_style: lambda { |cell|
                               cell.style.padding = [9, 8, 9, 0]
                               cell.style.border = { width: [cell.row.zero? ? 0 : 0.6, 0, 0, 0], color: LINIE }
                             })

      # Nachweise zum Dokument
      composer.text('DOKUMENT UND NACHWEISE', style: :abschnitt)
      dokument = select_attachments(submission.submitters.select(&:completed_at).max_by(&:completed_at)).first
      original = submission.schema_documents.first
      seiten_dok = begin
        HexaPDF::Document.new(io: StringIO.new(dokument.download)).pages.count if dokument
      rescue StandardError
        nil
      end
      zeile = ->(k, v) { [box.call([{ text: k, fill_color: GRAU }]), box.call([v].flatten)] }
      nachweise = [
        zeile.call('Umschlag-ID', submission.id.to_s),
        seiten_dok && zeile.call('Seiten im Dokument', seiten_dok.to_s),
        zeile.call('Erstellt', [zeit.call(submission.created_at),
                                submission.created_by_user && " von #{submission.created_by_user.full_name} (#{submission.created_by_user.email})"].compact.join),
        zeile.call('Ausgestellt über', "#{KnoppMarke::HOST} (#{KnoppMarke::FIRMA})"),
        original && zeile.call('Original (SHA-256)', { text: original.metadata['sha256'] || original.checksum, font_size: 7 }),
        dokument && zeile.call('Ergebnis (SHA-256)', { text: dokument.metadata['sha256'] || dokument.checksum, font_size: 7 })
      ].compact
      submitters.each do |item, s|
        fertig = submission.submission_events.find { |e| e.submitter_id == s.id && e.event_type == 'complete_form' }
        next unless fertig

        nachweise << zeile.call("Sitzung #{item['name']}", [{ text: "#{fertig.data['sid']}\n", font_size: 7 },
                                                             { text: fertig.data['ua'].to_s.squish, font_size: 6.5, fill_color: GRAU }])
        angaben = angaben(submission, s)
        nachweise << zeile.call("Angaben #{item['name']}", angaben.map { |k, v| "#{k}: #{v}" }.join("\n")) if angaben.any?
      end
      composer.table(nachweise, column_widths: [115, -1],
                                cell_style: lambda { |cell|
                                  cell.style.padding = [4, 8, 4, 8]
                                  cell.style.border = { width: 0 }
                                  cell.style.background_color = cell.row.even? ? 'ffffff' : nil
                                  cell.style.background_alpha = 0.75
                                })

      # Verlauf
      composer.text('VERLAUF', style: :abschnitt)
      verlauf = submission.submission_events.sort_by(&:event_timestamp).filter_map do |e|
        next if e.event_type.in?(%w[bounce_email complaint_email])

        s = submission.submitters.find { |x| x.id == e.submitter_id }
        wer = (s&.name || s&.email || s&.phone).to_s.squish
        teile = if (eigen = EREIGNISSE[e.event_type])
                  [eigen, wer]
                else
                  text = begin
                    I18n.t(e.event_type.include?('send_') ? "submission_event_names.#{e.event_type}_to_html" : "submission_event_names.#{e.event_type}_by_html",
                           submitter_name: wer, raise: true)
                  rescue I18n::MissingTranslationData
                    "<b>#{e.event_type.humanize}</b> #{wer}"
                  end
                  text.match(%r{<b>(.*?)</b>(.*)}m)&.captures || [text, '']
                end
        ip = e.data.is_a?(Hash) && e.data['ip'].present? && !e.data['ip'].match?(INTERN) ? "  · IP #{e.data['ip']}" : ''
        [box.call([{ text: zeit.call(e.event_timestamp), fill_color: GRAU, character_spacing: 0.3 }]),
         box.call([fett.call(teile[0]), teile[1].to_s.squish.prepend(' '), { text: ip, fill_color: GRAU }])]
      end
      if verlauf.any?
        composer.table(verlauf, column_widths: [125, -1],
                                cell_style: lambda { |cell|
                                  cell.style.padding = [4, 8, 4, 8]
                                  cell.style.border = { width: 0 }
                                  cell.style.background_color = cell.row.even? ? 'ffffff' : nil
                                  cell.style.background_alpha = 0.75
                                })
      end

      composer.formatted_text(
        [fett.call('Rechtlicher Hinweis: ', fill_color: GRAU),
         { text: 'Elektronische Signatur im Sinne von Art. 3 Nr. 10 der eIDAS-Verordnung (EU) Nr. 910/2014. ' \
                 'Die Unterzeichner wurden über ihre persönliche E-Mail-Adresse bzw. ihren persönlichen Link identifiziert. ' \
                 "Dokument und Zertifikat sind mit einem digitalen Siegel der Knopp Media GmbH (X.509, SHA-256) versiegelt; " \
                 'jede spätere Änderung macht das Siegel ungültig. Die Prüfsummen belegen, dass das Ergebnis aus dem Original entstanden ist. ' \
                 "Zeitangaben in #{timezone} (zusätzlich UTC beim Abschluss).", fill_color: GRAU }],
        font_size: 7, line_spacing: 1.3, padding: [14, 0, 0, 0]
      )

      # Fußzeile mit Seitenzahlen (erst jetzt bekannt)
      seiten = composer.document.pages.count
      composer.document.pages.each_with_index do |seite, i|
        canvas = seite.canvas(type: :overlay)
        canvas.font(font, size: 6.5).fill_color(GRAU)
        canvas.text("#{KnoppMarke::FIRMA} · Referenz #{referenz}", at: [58, 40])
        text = "Seite #{i + 1} von #{seiten}"
        breite = canvas.font.decode_utf8(text).sum(&:width) * 6.5 / 1000.0
        canvas.text(text, at: [seite.box(:media).width - 58 - breite, 40])
      end

      composer.document
    end
    # rubocop:enable Metrics

    # Papierton, Guilloche-Bänder oben und unten, Doppelrahmen; auf Seite 1 Siegel und Kreis hinter den Zeitstempeln
    def hintergrund(canvas, erste:)
      b = canvas.context.box(:media)
      w = b.width
      h = b.height
      canvas.save_graphics_state do
        canvas.fill_color(KnoppMarke::PAPIER).rectangle(0, 0, w, h).fill
        guilloche(canvas, 0, w, h - 26, 15)
        guilloche(canvas, 0, w, 16, 9)
        canvas.stroke_color(KnoppMarke::AKZENT).line_width(0.8).rectangle(24, 24, w - 48, h - 66).stroke
        canvas.stroke_color(KnoppMarke::FARBE).line_width(0.3).rectangle(28, 28, w - 56, h - 74).stroke
        if erste
          canvas.opacity(stroke_alpha: 0.35) do
            canvas.stroke_color(KnoppMarke::AKZENT).line_width(0.6).circle(w / 2.0 - 10, h - 345, 78).stroke
          end
          siegel(canvas, w - 96, h - 118, 30)
        end
      end
    end

    def guilloche(canvas, x0, x1, mitte, hoehe)
      canvas.opacity(stroke_alpha: 0.45) do
        [[KnoppMarke::FARBE, 0.0], [KnoppMarke::AKZENT, 0.9]].each do |farbe, versatz|
          canvas.stroke_color(farbe).line_width(0.3)
          8.times do |k|
            phase = (k * 0.42) + versatz
            punkte = (0..((x1 - x0) / 2.5).to_i).map do |i|
              x = x0 + (i * 2.5)
              [x, mitte + (hoehe * Math.sin((x / 19.0) + phase) * Math.cos((x / 61.0) - (phase * 0.6)))]
            end
            canvas.move_to(*punkte.first)
            punkte.drop(1).each { |p| canvas.line_to(*p) }
            canvas.stroke
          end
        end
      end
    end

    # Rosette wie ein Prägesiegel, Markenzeichen in der Mitte
    def siegel(canvas, cx, cy, r)
      canvas.opacity(stroke_alpha: 0.55) do
        canvas.stroke_color(KnoppMarke::AKZENT).line_width(0.35)
        24.times { |i| canvas.ellipse(cx, cy, a: r, b: r * 0.38, inclination: i * 7.5).stroke }
      end
      canvas.stroke_color(KnoppMarke::FARBE).line_width(1.2).circle(cx, cy, r + 5).stroke
      canvas.stroke_color(KnoppMarke::AKZENT).line_width(0.5).circle(cx, cy, r + 8).stroke
      canvas.fill_color(KnoppMarke::PAPIER).circle(cx, cy, r * 0.42).fill
      canvas.image(KnoppMarke::ZEICHEN, at: [cx - (r * 0.32), cy - (r * 0.32)], width: r * 0.64, height: r * 0.64) if File.exist?(KnoppMarke::ZEICHEN)
    end

    def geraet(ua)
      ua = ua.to_s
      browser = ua[/Edg\/(\d+)/] ? "Edge #{Regexp.last_match(1)}" : ua[/Firefox\/(\d+)/] ? "Firefox #{Regexp.last_match(1)}" :
                ua[/Chrome\/(\d+)/] ? "Chrome #{Regexp.last_match(1)}" : ua[/Version\/(\d+).*Safari/] ? "Safari #{Regexp.last_match(1)}" : 'Browser'
      system = { 'iPhone' => 'iPhone', 'iPad' => 'iPad', 'Android' => 'Android', 'Windows' => 'Windows', 'Mac OS X' => 'macOS',
                 'Linux' => 'Linux' }.find { |k, _| ua.include?(k) }&.last
      [browser, system].compact.join(' · ')
    end

    def unterschrift_bild(submission, submitter)
      feld = submission.template_fields.find { |f| f['submitter_uuid'] == submitter.uuid && f['type'] == 'signature' }
      anhang = feld && submitter.attachments.find { |a| a.uuid == submitter.values[feld['uuid']] }
      return unless anhang&.image?

      bild = ImageUtils.load_vips(anhang.download, content_type: anhang.content_type, autorot: true)
      bild = bild.resize([600.0 / bild.width, 600.0 / bild.height, 1].min)
      breite = 160.0
      hoehe = [bild.height * (breite / bild.width), 55].min
      breite = hoehe * bild.width / bild.height
      { io: StringIO.new(bild.write_to_buffer('.png', strip: true)), breite:, hoehe: }
    rescue StandardError
      nil
    end

    def angaben(submission, submitter)
      submission.template_fields.filter_map do |f|
        next if f['submitter_uuid'] != submitter.uuid || !f['type'].in?(%w[text number date])

        wert = submitter.values[f['uuid']]
        next if wert.blank?

        wert = TimeUtils.format_date_string(wert, f.dig('preferences', 'format'), submission.account.locale) if f['type'] == 'date'
        [f['name'], wert.to_s.squish.truncate(60)]
      end.first(12)
    end
  end
end

Rails.application.config.to_prepare do
  Docuseal.singleton_class.prepend(KnoppMarke::Produkt)
  Submissions::GenerateResultAttachments.singleton_class.prepend(KnoppMarke::Signatur)
  Submissions::GenerateAuditTrail.singleton_class.prepend(KnoppMarke::Zertifikat)
end
