# toolchain-fix

일부 Mac의 Command Line Tools 설치에는 예전 버전이 남긴
`/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap` 이
새 `bridging.modulemap` 과 함께 남아 있어서, 모든 Swift 컴파일이
`redefinition of module 'SwiftBridging'` 으로 실패합니다.

`build.sh` 는 두 파일이 모두 있을 때만 `overlay.yaml.in` 으로 VFS 오버레이를 만들어
오래된 파일을 빈 파일(`empty.modulemap`)로 가린 채 컴파일합니다 (sudo 불필요).

근본적인 해결은 CLT 재설치입니다:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```
