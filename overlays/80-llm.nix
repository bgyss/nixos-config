final: prev: {
  python312Packages = prev.python312Packages.overrideScope (
    pyFinal: pyPrev: {
      llm = pyPrev.llm.overridePythonAttrs (_old: {
        doCheck = false;
      });
    }
  );
}
