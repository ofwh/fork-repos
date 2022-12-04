// generate .drone.yaml, run:
// drone jsonnet --format --stream


local CreateRelease() = {
  name: 'create release',
  image: 'plugins/gitea-release',
  settings: {
    api_key: { from_secret: 'GITEA_API_KEY' },
    base_url: 'https://git.unlock-music.dev',
    files: 'dist/*',
    checksum: 'sha256',
    draft: true,
    title: '${DRONE_TAG}',
  },
};


local StepGoBuild(GOOS, GOARCH) = {
  local filepath = 'dist/um-%s-%s.tar.gz' % [GOOS, GOARCH],

  name: 'go build %s/%s' % [GOOS, GOARCH],
  image: 'golang:1.19',
  environment: {
    GOOS: GOOS,
    GOARCH: GOARCH,
  },
  commands: [
    'DIST_DIR=$(mktemp -d)',
    'go build -v -trimpath -ldflags="-w -s -X main.AppVersion=$(git describe --tags --always)" -o $DIST_DIR ./cmd/um',
    'mkdir -p dist',
    'tar cz -f %s -C $DIST_DIR .' % filepath,
  ],
};

local StepUploadArtifact(GOOS, GOARCH) = {
  local filename = 'um-%s-%s.tar.gz' % [GOOS, GOARCH],
  local filepath = 'dist/%s' % filename,
  local pkgname = '${DRONE_REPO_NAME}-build',

  name: 'upload artifact',
  image: 'golang:1.19',  // reuse golang:1.19 for curl
  environment: {
    DRONE_GITEA_SERVER: 'https://git.unlock-music.dev',
    GITEA_API_KEY: { from_secret: 'GITEA_API_KEY' },
  },
  commands: [
    'curl --fail --include --user "um-release-bot:$GITEA_API_KEY" ' +
    '--upload-file "%s" ' % filepath +
    '"$DRONE_GITEA_SERVER/api/packages/${DRONE_REPO_NAMESPACE}/generic/%s/${DRONE_BUILD_NUMBER}/%s"' % [pkgname, filename],
    'sha256sum %s' % filepath,
    'echo $DRONE_GITEA_SERVER/${DRONE_REPO_NAMESPACE}/-/packages/generic/%s/${DRONE_BUILD_NUMBER}' % pkgname,
  ],
};


local PipelineBuild(GOOS, GOARCH, RUN_TEST) = {
  name: 'build %s/%s' % [GOOS, GOARCH],
  kind: 'pipeline',
  type: 'docker',
  steps: [
           {
             name: 'fetch tags',
             image: 'alpine/git',
             commands: ['git fetch --tags'],
           },
         ] +
         (
           if RUN_TEST then [{
             name: 'go test',
             image: 'golang:1.19',
             commands: [
              'apt-get update && apt-get -y install zlib1g-dev',
              'go test -v ./...'
              ],
           }] else []
         )
         +
         [
           StepGoBuild(GOOS, GOARCH),
           StepUploadArtifact(GOOS, GOARCH),
         ],
  trigger: {
    event: ['push', 'pull_request'],
  },
};

local PipelineRelease() = {
  name: 'release',
  kind: 'pipeline',
  type: 'docker',
  steps: [
    {
      name: 'fetch tags',
      image: 'alpine/git',
      commands: ['git fetch --tags'],
    },
    {
      name: 'go test',
      image: 'golang:1.19',
      commands: ['go test -v ./...'],
    },
    StepGoBuild('linux', 'amd64'),
    StepGoBuild('linux', 'arm64'),
    StepGoBuild('linux', '386'),
    StepGoBuild('windows', 'amd64'),
    StepGoBuild('windows', '386'),
    StepGoBuild('darwin', 'amd64'),
    StepGoBuild('darwin', 'arm64'),
    CreateRelease(),
  ],
  trigger: {
    event: ['tag'],
  },
};

[
  PipelineBuild('linux', 'amd64', true),
  PipelineBuild('windows', 'amd64', false),
  PipelineBuild('darwin', 'amd64', false),
  PipelineRelease(),
]
