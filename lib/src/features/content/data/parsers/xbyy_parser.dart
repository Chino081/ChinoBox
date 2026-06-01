import '../../../source/domain/source_catalog.dart';
import 'generic_maccms_parser.dart';

class XbyyParser extends GenericMaccmsParser {
  XbyyParser()
      : super(
          sourceById('xbyy'),
          searchTemplate: '/index.php/vod/search/page/%p/wd/%s.html',
          categoryTemplate: '/index.php/vod/show/id/%s/page/%p.html',
        );
}
