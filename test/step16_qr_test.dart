import 'package:all_in_one/modules/qr/qr_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kinds', () {
    test('new kinds are recognised', () {
      expect(QrContent('smsto:+33612:Salut').kind, QrKind.sms);
      expect(QrContent('SMS:+33612?body=Hi').kind, QrKind.sms);
      expect(QrContent('geo:48.85,2.35').kind, QrKind.geo);
      expect(QrContent('BEGIN:VCARD\nFN:A\nEND:VCARD').kind, QrKind.contact);
      expect(QrContent('MECARD:N:Durand,Paul;;').kind, QrKind.contact);
      expect(QrContent('https://exemple.fr').kind, QrKind.url);
      expect(QrContent('bonjour').kind, QrKind.text);
    });

    test('sms number and message', () {
      final a = QrContent('smsto:+33612345678:Rendez-vous à 8 h').sms;
      expect((a.number, a.body), ('+33612345678', 'Rendez-vous à 8 h'));
      final b = QrContent('sms:+33612?body=Hello%20you').sms;
      expect((b.number, b.body), ('+33612', 'Hello you'));
      final c = QrContent('smsto:0612').sms;
      expect((c.number, c.body), ('0612', ''));
      // A colon inside the message stays in the message.
      expect(QrContent('smsto:0612:a:b').sms.body, 'a:b');
    });

    test('geo coordinates are validated', () {
      final g = QrContent('geo:48.8566,2.3522?q=Paris').geo!;
      expect((g.lat, g.lon), (48.8566, 2.3522));
      expect(QrContent('geo:-33.86,151.2').geo!.lat, -33.86);
      expect(QrContent('geo:95,2').geo, isNull);
      expect(QrContent('geo:abc').geo, isNull);
      expect(QrContent('texte').geo, isNull);
    });
  });

  group('contacts', () {
    test('vCard with folded lines, escapes and several numbers', () {
      final c = parseContact(
        'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Durand;Paul;;;\r\nFN:Paul Durand\r\n'
        'ORG:Société\\, Martin;Ventes\r\nTEL;TYPE=CELL:+33 6 12 34 56 78\r\n'
        'TEL;TYPE=WORK:01 02 03 04 05\r\nEMAIL:paul@exemple.fr\r\n'
        'ADR;TYPE=HOME:;;12 rue des Lilas;Lyon;;69003;France\r\n'
        'URL:https://exemple.fr\r\nNOTE:ligne\r\n  suite\r\nEND:VCARD',
      )!;
      expect(c.name, 'Paul Durand');
      expect(c.phones, ['+33 6 12 34 56 78', '01 02 03 04 05']);
      expect(c.emails, ['paul@exemple.fr']);
      expect(c.organization, 'Société, Martin Ventes');
      expect(c.address, '12 rue des Lilas, Lyon, 69003, France');
      expect(c.url, 'https://exemple.fr');
    });

    test('vCard without FN builds the name from N', () {
      final c = parseContact('BEGIN:VCARD\nN:Curie;Marie;;;\nEND:VCARD')!;
      expect(c.name, 'Marie Curie');
    });

    test('MECARD', () {
      final c = parseContact(
        r'MECARD:N:Durand,Paul;TEL:0612345678;EMAIL:p@ex.fr;ORG:Acme\; Inc;ADR:1 rue A\, Lyon;;',
      )!;
      expect(c.name, 'Paul Durand');
      expect(c.phones, ['0612345678']);
      expect(c.emails, ['p@ex.fr']);
      expect(c.organization, 'Acme; Inc');
      expect(c.address, '1 rue A, Lyon');
    });

    test('empty or foreign text is not a contact', () {
      expect(parseContact('BEGIN:VCARD\nEND:VCARD'), isNull);
      expect(parseContact('MECARD:;;'), isNull);
      expect(parseContact('bonjour'), isNull);
      expect(QrContent('BEGIN:VCARD\nEND:VCARD').contact, isNull);
    });

    test(
      'a created vCard reads back the same, special characters included',
      () {
        const card = QrContact(
          name: 'Marie-Anne de La Tour',
          phones: ['+33 6 00 00 00 01'],
          emails: ['m@ex.fr'],
          organization: 'Dupont; Fils, SA',
          url: 'https://ex.fr/a;b',
        );
        final code = vcardCode(card);
        expect(code.startsWith('BEGIN:VCARD\nVERSION:3.0'), isTrue);
        final back = parseContact(code)!;
        expect(back.name, 'Marie-Anne de La Tour');
        expect(back.phones, card.phones);
        expect(back.emails, card.emails);
        expect(back.organization, 'Dupont; Fils, SA');
        expect(back.url, 'https://ex.fr/a;b');
        expect(QrContent(code).display, 'Marie-Anne de La Tour');
      },
    );

    test('a one-word name still makes a valid card', () {
      final back = parseContact(vcardCode(const QrContact(name: 'Cher')))!;
      expect(back.name, 'Cher');
    });
  });

  group('wifi codes', () {
    test('security, hidden flag and escaping', () {
      expect(wifiCode('Maison', 'secret'), 'WIFI:S:Maison;T:WPA;P:secret;;');
      expect(
        wifiCode('Maison', 'secret', security: WifiSecurity.wep),
        'WIFI:S:Maison;T:WEP;P:secret;;',
      );
      expect(
        wifiCode('Café', '', hidden: true),
        'WIFI:S:Café;T:nopass;H:true;;',
      );
      // Without a password the network is open even if WPA was asked.
      expect(
        wifiCode('Libre', '', security: WifiSecurity.wpa),
        'WIFI:S:Libre;T:nopass;;',
      );
      final tricky = wifiCode('A;B', 'p:w"d', hidden: true);
      final read = QrContent(tricky);
      expect(read.wifiName, 'A;B');
      expect(read.wifiPassword, 'p:w"d');
      expect(read.wifi['H'], 'true');
      expect(read.wifi['T'], 'WPA');
    });
  });
}
