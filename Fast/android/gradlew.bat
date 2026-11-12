@echo off
setlocal
set APP_HOME=%~dp0
set WRAPPER_DIR=%APP_HOME%gradle\wrapper
set WRAPPER_JAR=%WRAPPER_DIR%\gradle-wrapper.jar
set WRAPPER_URL=https://raw.githubusercontent.com/gradle/gradle/v8.13.0/gradle/wrapper/gradle-wrapper.jar
set EXPECTED_SHA256=81a82aaea5abcc8ff68b3dfcb58b3c3c429378efd98e7433460610fecd7ae45f
if not exist "%WRAPPER_JAR%" (
  if not exist "%WRAPPER_DIR%" mkdir "%WRAPPER_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing '%WRAPPER_URL%' -OutFile '%WRAPPER_JAR%.tmp'; if ((Get-FileHash '%WRAPPER_JAR%.tmp' -Algorithm SHA256).Hash.ToLower() -ne '%EXPECTED_SHA256%') { Remove-Item '%WRAPPER_JAR%.tmp' -Force; throw 'Gradle Wrapper JAR checksum mismatch' }; Move-Item '%WRAPPER_JAR%.tmp' '%WRAPPER_JAR%' -Force"
  if errorlevel 1 exit /b 1
)
java %JAVA_OPTS% %GRADLE_OPTS% -Dorg.gradle.appname=gradlew -classpath "%WRAPPER_JAR%" org.gradle.wrapper.GradleWrapperMain %*
endlocal
exit /b %ERRORLEVEL%
