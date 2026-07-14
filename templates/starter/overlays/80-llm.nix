final: prev: {
  python312Packages = prev.python312Packages // {
    llm = prev.python312Packages.llm.overridePythonAttrs {
      doCheck = false;
    };
  };
}
