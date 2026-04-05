library dartdata_generator;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/model_generator.dart';

/// Entry point for build_runner.
Builder dartdataBuilder(BuilderOptions options) =>
    SharedPartBuilder([ModelGenerator()], 'dartdata');
