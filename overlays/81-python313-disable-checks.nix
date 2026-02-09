final: prev: {
  python313Packages = prev.python313Packages.overrideScope (
    pyFinal: pyPrev: {
      prometheus-client = pyPrev.prometheus-client.overridePythonAttrs (_old: {
        doCheck = false;
      });
      testfixtures = pyPrev.testfixtures.overridePythonAttrs (_old: {
        doCheck = false;
      });
      bump2version = pyPrev.bump2version.overridePythonAttrs (_old: {
        doCheck = false;
      });
      twisted = pyPrev.twisted.overridePythonAttrs (_old: {
        doCheck = false;
      });
      ffmpeg-python = pyPrev.ffmpeg-python.overridePythonAttrs (_old: {
        doCheck = false;
      });
      paramiko = pyPrev.paramiko.overridePythonAttrs (_old: {
        doCheck = false;
        pythonRuntimeDepsCheck = "disabled";
        dontCheckRuntimeDeps = true;
      });
    }
  );
}
