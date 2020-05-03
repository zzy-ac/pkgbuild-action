# Maintainer: Eric Langlois <eric@langlois.xyz>
pkgname=(aurvote-version)
pkgver=1.0.0
pkgrel=1
pkgdesc="Prints the version of aurvote"
url="http://www.example.com"
arch=('any')
license=('MIT')
depends=(bash aurvote)
checkdepends=()
makedepends=()
source=(aurvote-version.sh LICENSE)
sha256sums=(
	'082e4952418f5855fadef75abcc45cf980aab7e70f4583b44e5dc08ce90ab2e7'
	'943b0a306fec2cbb9368f82d363a1165d26b49dbfef9065c61633a8abeb14027'
)

build() {
	cp aurvote-version.sh aurvote-version
	chmod u+x aurvote-version
}

check() {
	./aurvote-version
}

package() {
	install -m755 -D "aurvote-version" "$pkgdir/usr/bin/aurvote-version"
	install -Dm644 "LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
