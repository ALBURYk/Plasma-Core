export 'researcher_workspace_stub.dart'
    if (dart.library.io) 'researcher_workspace_native.dart'
    if (dart.library.html) 'researcher_workspace_web.dart';
