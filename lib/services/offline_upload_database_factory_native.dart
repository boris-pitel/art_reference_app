import 'package:idb_shim/idb_io.dart';
import 'package:path_provider/path_provider.dart';

Future<IdbFactory> createOfflineUploadDatabaseFactory() async {
  final directory = await getApplicationSupportDirectory();
  return getIdbFactoryPersistent(directory.path);
}
