import '../../../source/domain/source_catalog.dart';
import 'generic_maccms_parser.dart';

class ZxzjParser extends GenericMaccmsParser {
  ZxzjParser()
      : super(
          sourceById('zxzj'),
          searchTemplate: '/search/%s----------%p---.html',
          categoryTemplate: '/show/%s--------%p---.html',
        );
}
