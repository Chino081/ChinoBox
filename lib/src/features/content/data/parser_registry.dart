import '../../source/domain/source_catalog.dart';
import '../domain/content_models.dart';
import 'parsers/anfuns_parser.dart';
import 'parsers/five_movie_parser.dart';
import 'parsers/girigirilove_parser.dart';
import 'parsers/iyinghua_parser.dart';
import 'parsers/libvio_parser.dart';
import 'parsers/nyyy_parser.dart';
import 'parsers/silisili_parser.dart';
import 'parsers/tbys_parser.dart';
import 'parsers/xbyy_parser.dart';
import 'parsers/yjys_parser.dart';
import 'parsers/zxzj_parser.dart';
import 'site_parser.dart';

class ParserRegistry {
  ParserRegistry._();

  static final Map<String, SiteParser> _parsers = {
    'tbys': TbysParser(),
    'silisili': SilisiliParser(),
    'iyinghua': IYingHuaParser(),
    'anfuns': AnFunsParser(),
    'libvio': LibvioParser(),
    'zxzj': ZxzjParser(),
    'five_movie': FiveMovieParser(),
    'yjys': YjysParser(),
    'xbyy': XbyyParser(),
    'nyyy': NyyyParser(),
    'girigirilove': GiriGiriLoveParser(),
  };

  static SiteParser byId(String sourceId) {
    return _parsers[sourceId] ?? _parsers[defaultSourceId]!;
  }
}

class HomePayload {
  const HomePayload({
    required this.sourceId,
    required this.sections,
    required this.categories,
    this.notice = '',
  });

  final String sourceId;
  final List<HomeSection> sections;
  final List<CategoryGroup> categories;
  final String notice;
}
