import '../../../source/domain/source_catalog.dart';
import '../site_parser.dart';

class FiveMovieParser extends UnavailableParser {
  FiveMovieParser() : super(sourceById('five_movie'));
}
