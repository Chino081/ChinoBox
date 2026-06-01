import '../../../source/domain/source_catalog.dart';
import 'generic_maccms_parser.dart';

class NyyyParser extends GenericMaccmsParser {
  NyyyParser()
      : super(
          sourceById('nyyy'),
          searchTemplate: '/vodsearch/%s----------%p---.html',
          categoryTemplate: '/vodshow/%s-----%p---.html',
        );
}
