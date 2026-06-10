// CI for the PC Kaiser mobile clone (Jenkins on VPC).
//
// Expects a Flutter SDK on the agent. Point FLUTTER_HOME at it (defaults to
// /opt/flutter) or pre-bake it into the agent image; flutter/bin provides
// both `flutter` and `dart`.
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        FLUTTER_HOME = "${env.FLUTTER_HOME ?: '/opt/flutter'}"
        PATH = "${env.PATH}:${env.FLUTTER_HOME ?: '/opt/flutter'}/bin"
        PUB_CACHE = "${env.WORKSPACE}/.pub-cache"
    }

    stages {
        stage('Toolchain') {
            steps {
                sh 'flutter --version'
            }
        }

        stage('game_core') {
            steps {
                dir('packages/game_core') {
                    sh 'dart pub get'
                    sh 'dart analyze --fatal-infos'
                    sh 'dart test --reporter expanded'
                }
            }
        }

        stage('client') {
            steps {
                dir('client') {
                    sh 'flutter pub get'
                    sh 'flutter analyze'
                    sh 'flutter test'
                }
            }
        }
    }
}
