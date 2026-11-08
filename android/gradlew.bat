@echo off
setlocal
set APP_HOME=%~dp0
if exist "%APP_HOME%gradle\wrapper\gradle-wrapper.jar" (
  if defined JAVA_HOME (
    set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
  ) else (
    set "JAVA_EXE=java.exe"
  )
  "%JAVA_EXE%" %JAVA_OPTS% -classpath "%APP_HOME%gradle\wrapper\gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain %*
  exit /b %ERRORLEVEL%
)
where gradle.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  gradle %*
  exit /b %ERRORLEVEL%
)
echo Gradle wrapper JAR is generated automatically by codemagic.yaml. Locally run: flutter create --platforms=android .
exit /b 1
