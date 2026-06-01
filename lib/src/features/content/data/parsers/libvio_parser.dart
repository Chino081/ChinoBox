import '../../../source/domain/source_catalog.dart';
import 'generic_maccms_parser.dart';

class LibvioParser extends GenericMaccmsParser {
  LibvioParser()
      : super(
          sourceById('libvio'),
          searchTemplate: '/search/%s----------%p---.html',
          categoryTemplate: '/show/%s--------%p---.html',
        );
}
