// Casa Pazza server: PocketBase with the JS migrations/hooks from this repo
// plus FCM push notifications (push.go), which need RS256 signing that the
// JS hooks cannot do.
package main

import (
	"log"
	"net/http"
	"os"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/jsvm"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
)

func main() {
	app := pocketbase.New()

	// Same flags as the official binary, so entrypoint.sh stays unchanged.
	var hooksDir, migrationsDir, publicDir string
	var hooksWatch, automigrate bool
	flags := app.RootCmd.PersistentFlags()
	flags.StringVar(&hooksDir, "hooksDir", "", "the directory with the JS app hooks")
	flags.BoolVar(&hooksWatch, "hooksWatch", false, "auto restart the app on pb_hooks file change")
	flags.StringVar(&migrationsDir, "migrationsDir", "", "the directory with the user defined migrations")
	flags.BoolVar(&automigrate, "automigrate", false, "auto generate migrations from dashboard changes")
	flags.StringVar(&publicDir, "publicDir", "", "the directory to serve static files (the web app) from")
	app.RootCmd.ParseFlags(os.Args[1:])

	jsvm.MustRegister(app, jsvm.Config{
		MigrationsDir: migrationsDir,
		HooksDir:      hooksDir,
		HooksWatch:    hooksWatch,
	})
	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		TemplateLang: migratecmd.TemplateLangJS,
		Automigrate:  automigrate,
		Dir:          migrationsDir,
	})

	registerPush(app)

	// Serves the web app (built into the Docker image) like the official
	// binary serves pb_public.
	if publicDir != "" {
		app.OnServe().BindFunc(func(e *core.ServeEvent) error {
			if !e.Router.HasRoute(http.MethodGet, "/{path...}") {
				e.Router.GET("/{path...}", apis.Static(os.DirFS(publicDir), true))
			}
			return e.Next()
		})
	}

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
