#!/bin/bash

src=$1

sed -i "s/List excludePlatforms = \[/&'linux-loongarch64', /" "$src/distribution/build.gradle"
sed -i "/from project.jdks./i\\
        if (os == 'linux' && architecture == 'loongarch64') {\\
          from localBundledJdkHome(project)\\
        } else {" "$src/distribution/build.gradle"
sed -i "/from project.jdks./a\\
        }" "$src/distribution/build.gradle"

cat << 'EOF' > $patches/insert_block
    localBundledJdkHome = { Project project ->
      String propertyName = 'loongarchBundledJdkHome'
      Object propertyValue = project.findProperty(propertyName)
      if (propertyValue == null) {
        throw new GradleException("Property [${propertyName}] must point to the JDK to bundle in linux-loongarch64 distributions")
      }

      File javaHome = project.file(propertyValue.toString())
      if (javaHome.isDirectory() == false) {
        throw new GradleException("Bundled linux-loongarch64 JDK home [${javaHome}] does not exist or is not a directory")
      }

      File releaseFile = new File(javaHome, 'release')
      if (releaseFile.isFile() == false) {
        throw new GradleException("Bundled linux-loongarch64 JDK home [${javaHome}] is missing [release]")
      }

      Properties releaseProperties = new Properties()
      releaseFile.withInputStream { releaseProperties.load(it) }

      String javaVersion = releaseProperties.getProperty('JAVA_VERSION')?.replace('"', '')
      if (javaVersion == null) {
        throw new GradleException("Bundled linux-loongarch64 JDK release file [${releaseFile}] is missing JAVA_VERSION")
      }

      String expectedMajor = VersionProperties.bundledJdkVersion.split('[+.]')[0]
      String actualMajor = javaVersion.startsWith('1.') ? javaVersion.split('\\.')[1] : javaVersion.split('\\.')[0]
      if (actualMajor != expectedMajor) {
        throw new GradleException(
          "Bundled linux-loongarch64 JDK at [${javaHome}] has major version [${actualMajor}], expected [${expectedMajor}]"
        )
      }

      return javaHome
    }
EOF

sed -i "/project.ext {/r $patches/insert_block" "$src/distribution/build.gradle"

