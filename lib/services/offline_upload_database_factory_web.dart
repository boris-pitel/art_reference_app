import 'package:idb_shim/idb_browser.dart';

Future<IdbFactory> createOfflineUploadDatabaseFactory() async {
  return idbFactoryBrowser;
}
