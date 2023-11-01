article: check-arg
	npx zenn new:article --slug $(title) --title $(title)

book: check-arg
	npx zenn new:book --slug $(title) --title $(title)

check-arg:
ifndef title
	@ echo "title = about-me"
	@ echo "Usage: make <command> title=about-me"
	@ exit 1
endif

.PHONY: article book
