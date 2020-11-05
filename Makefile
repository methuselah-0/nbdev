SRC = $(wildcard nbs/*.ipynb)

all: nbdev docs

nbdev: $(SRC)
	nbdev_build_lib
	touch nbdev

docs_serve: docs
	cd docs && GEM_HOME=~/gems GEM_PATH=~/gems/bin gem install bundler:2.0.2 && GEM_HOME=~/gems GEM_PATH=~/gems/bin LD_LIBRARY_PATH=~/.guix-profile/lib bundle exec jekyll serve

docs: $(SRC)
	nbdev_build_docs
	touch docs

test:
	nbdev_test_nbs

release: pypi
	nbdev_bump_version

pypi: dist
	twine upload --repository pypi dist/*

dist: clean
	python setup.py sdist bdist_wheel

clean:
	rm -rf dist

