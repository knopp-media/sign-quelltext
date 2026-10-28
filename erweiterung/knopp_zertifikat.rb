# frozen_string_literal: true

# Knopp Media Sign: eigenes Abschlusszertifikat statt des DocuSeal-Prüfprotokolls (Aufbau angelehnt an das
# „Signature Certificate“ von PandaDoc) und Marke statt „DocuSeal“ in Signatur, PDF-Metadaten und Mails.
# Eingebunden per Compose als config/initializers/knopp_zertifikat.rb. Ersetzt nur Methoden (prepend),
# DocuSeal-Dateien bleiben unverändert; branding/pruefen.sh hält das Ausrollen an, wenn sich die
# benutzten DocuSeal-Teile ändern (erweiterung/abhaengig.sha256).
module KnoppMarke
  NAME = ENV.fetch('SIGN_MARKE', 'Knopp Media')
  PK = NAME == 'PresseKreis'
  HOST = ENV.fetch('HOST', PK ? 'sign.pressekreis.de' : 'sign.knopp-media.de')
  FIRMA = PK ? 'PresseKreis · Ein Service der Knopp Media GmbH' : 'Knopp Media GmbH'
  FARBE = PK ? '020b23' : 'ff8a00'      # Hauptfarbe (Logo)
  AKZENT = PK ? 'd6a64d' : '222222'     # Kante unter dem Streifen
  LOGO = '/app/public/branding/logo.png'
  LOGO_BREITE = PK ? 150 : 118          # Punkte, Höhe ergibt sich aus 120 px Bildhöhe

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
    LINIE = 'e3e6ec'
    FLAECHE = 'f5f6f8'
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
      zeit = ->(t) { t && "#{t.in_time_zone(timezone).strftime('%d.%m.%Y, %H:%M:%S')} #{TimeUtils.timezone_abbr(timezone, t)}" }
      fett = ->(text, **o) { { text: text.to_s, font: [font, { variant: :bold }], **o } }
      referenz = Digest::MD5.hexdigest(submission.slug).upcase
      titel = submission.name || submission.template&.name || 'Dokument'
      submitters = submission.template_submitters.filter_map { |i| [i, submission.submitters.find { |s| s.uuid == i['uuid'] }] }
                             .select { |_, s| s }
      abgeschlossen = submission.submitters.filter_map(&:completed_at).max

      composer.page_style(:default, page_size: :A4) do |canvas, style|
        box = canvas.context.box(:media)
        canvas.save_graphics_state do
          canvas.fill_color(KnoppMarke::FARBE).rectangle(0, box.height - 8, box.width, 8).fill
          canvas.fill_color(KnoppMarke::AKZENT).rectangle(0, box.height - 10, box.width, 2).fill
          canvas.stroke_color(LINIE).line_width(0.5).line(50, 42, box.width - 50, 42).stroke
        end
        style.frame = style.create_frame(canvas.context, [55, 50, 60, 50])
      end
      composer.style(:base, font:, font_size: 9, fill_color: TEXT, line_spacing: 1.25)
      composer.style(:klein, font:, font_size: 7.5, fill_color: GRAU, line_spacing: 1.25)
      composer.style(:abschnitt, font: [font, { variant: :bold }], font_size: 8, fill_color: GRAU, character_spacing: 0.8,
                                 padding: [16, 0, 6, 0])
      composer.new_page

      # Kopf: Logo links, Titel rechts
      if File.exist?(KnoppMarke::LOGO)
        composer.image(KnoppMarke::LOGO, width: KnoppMarke::LOGO_BREITE, position: :float, margin: [4, 0, 0, 0])
      end
      composer.formatted_text([fett.call('Abschlusszertifikat', font_size: 18), "\n",
                               { text: "Elektronische Unterschrift über #{KnoppMarke::HOST}", font_size: 8, fill_color: GRAU }],
                              text_align: :right, padding: [0, 0, 14, 0])
      composer.box(:base, height: 1, style: { background_color: KnoppMarke::AKZENT == '222222' ? KnoppMarke::FARBE : KnoppMarke::AKZENT,
                                              margin: [0, 0, 6, 0] })

      # Übersicht wie bei PandaDoc: Dokument, Referenz, Zeitpunkte, Prüfsummen
      dokument = select_attachments(submission.submitters.select(&:completed_at).max_by(&:completed_at)).first
      original = submission.schema_documents.first
      zeile = ->(k, v) { [composer.document.layout.formatted_text_box([{ text: k, fill_color: GRAU }]),
                          composer.document.layout.formatted_text_box([v].flatten)] }
      uebersicht = [
        zeile.call('Dokument', fett.call(titel)),
        zeile.call('Referenznummer', referenz),
        zeile.call('Umschlag-ID', submission.id.to_s),
        zeile.call('Erstellt', [zeit.call(submission.created_at), submission.created_by_user && " von #{submission.created_by_user.full_name}"].compact.join),
        zeile.call('Abgeschlossen', zeit.call(abgeschlossen) || 'offen'),
        zeile.call('Unterzeichner', submitters.size.to_s),
        original && zeile.call('Original (SHA-256)', { text: original.metadata['sha256'] || original.checksum, font_size: 7.5 }),
        dokument && zeile.call('Ergebnis (SHA-256)', { text: dokument.metadata['sha256'] || dokument.checksum, font_size: 7.5 })
      ].compact
      composer.table(uebersicht, column_widths: [110, -1],
                                 cell_style: { padding: [4, 10, 4, 10], border: { width: 0 }, background_color: FLAECHE })

      # Unterzeichner: je eine Karte mit Person, Zeitpunkten/Nachweisen und Unterschrift
      composer.text('UNTERZEICHNER', style: :abschnitt)
      submitters.each do |item, s|
        events = submission.submission_events.select { |e| e.submitter_id == s.id }
        erstes = ->(typ) { events.select { |e| e.event_type == typ }.min_by(&:event_timestamp) }
        fertig = erstes.call('complete_form')
        api = erstes.call('api_complete_form')
        geklickt = events.any? { |e| e.event_type.in?(%w[click_email email_verified]) }

        person = [fett.call(s.name.presence || s.email, font_size: 10), "\n",
                  { text: "#{item['name']}\n", fill_color: GRAU }, s.email.to_s, "\n",
                  geklickt ? { text: "\n✓ Über den persönlichen E-Mail-Link geöffnet", fill_color: '1f8a55', font_size: 7.5 } : '']
        nachweise = [
          ['Gesendet', zeit.call(erstes.call('send_email')&.event_timestamp)],
          ['Angesehen', zeit.call(erstes.call('view_form')&.event_timestamp)],
          ['Unterschrieben', zeit.call(fertig&.event_timestamp)],
          api && ['Abgeschlossen', "#{zeit.call(api.event_timestamp)} (ausgefüllt, ohne Unterschrift)"],
          fertig&.data&.dig('ip') && ['IP-Adresse', fertig.data['ip']],
          fertig&.data&.dig('ua') && ['Gerät', geraet(fertig.data['ua'])],
          s.timezone && ['Zeitzone', s.timezone.to_s]
        ].compact.select { |_, v| v.present? }.flat_map { |k, v| [{ text: "#{k}: ", fill_color: GRAU }, "#{v}\n"] }

        bild = unterschrift_bild(submission, s)
        rechts = if bild
                   composer.document.layout.image_box(bild[:io], width: bild[:breite], height: bild[:hoehe])
                 else
                   composer.document.layout.formatted_text_box([{ text: api ? 'keine Unterschrift nötig' : '–', fill_color: GRAU }])
                 end
        composer.table([[composer.document.layout.formatted_text_box(person),
                         composer.document.layout.formatted_text_box(nachweise.presence || [{ text: 'noch offen', fill_color: GRAU }]),
                         rechts]],
                       column_widths: [150, -1, 165],
                       cell_style: { padding: [10, 10, 10, 10], border: { width: [0.6, 0, 0.6, 0], color: LINIE } },
                       margin: [0, 0, 8, 0])

        angaben = angaben(submission, s)
        if angaben.any?
          composer.formatted_text(angaben.flat_map { |k, v| [{ text: "#{k}: ", fill_color: GRAU }, "#{v}   "] },
                                  style: :klein, padding: [0, 0, 10, 0])
        end
      end

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
        # interne Adressen (Aufrufe aus dem Assistenten im Docker-Netz) nicht als IP des Unterzeichners zeigen
        ip = e.data.is_a?(Hash) && e.data['ip'].present? && !e.data['ip'].match?(/\A(10|127|172\.(1[6-9]|2\d|3[01])|192\.168)\./) ? "  · IP #{e.data['ip']}" : ''
        [composer.document.layout.formatted_text_box([{ text: zeit.call(e.event_timestamp), fill_color: GRAU }]),
         composer.document.layout.formatted_text_box([fett.call(teile[0]), teile[1].to_s.squish.prepend(' '), { text: ip, fill_color: GRAU }])]
      end
      if verlauf.any?
        composer.table(verlauf, column_widths: [135, -1],
                                cell_style: lambda { |cell|
                                  cell.style.padding = [5, 8, 5, 8]
                                  cell.style.border = { width: 0 }
                                  cell.style.background_color = cell.row.even? ? FLAECHE : 'ffffff'
                                })
      end

      composer.formatted_text(
        [{ text: abgeschlossen ? "Von allen Parteien elektronisch unterschrieben am #{zeit.call(abgeschlossen)}. " : '' },
         { text: "Das Dokument und dieses Zertifikat sind digital versiegelt. Jede spätere Änderung macht die Signatur ungültig. Die Prüfsummen oben belegen, dass das Ergebnis aus dem Original entstanden ist." }],
        style: :klein, padding: [16, 0, 0, 0]
      )

      # Fußzeile mit Seitenzahlen (erst jetzt bekannt)
      seiten = composer.document.pages.count
      composer.document.pages.each_with_index do |seite, i|
        canvas = seite.canvas(type: :overlay)
        canvas.font(font, size: 7).fill_color(GRAU)
        canvas.text("#{KnoppMarke::FIRMA} · Referenz #{referenz}", at: [50, 30])
        breite = canvas.font.decode_utf8("Seite #{i + 1} von #{seiten}").sum { |g| g.width } * 7 / 1000.0
        canvas.text("Seite #{i + 1} von #{seiten}", at: [seite.box(:media).width - 50 - breite, 30])
      end

      composer.document
    end
    # rubocop:enable Metrics

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
      breite = 135.0
      hoehe = [bild.height * (breite / bild.width), 60].min
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
