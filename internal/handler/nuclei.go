// handle-------------------------------------
// @file      : nuclei.go
// @author    : Autumn
// @contact   : rainy-autumn@outlook.com
// @time      : 2024/10/20 14:48
// -------------------------------------------

package handler

import (
	"context"
	"fmt"
	"github.com/Autumn-27/ScopeSentry-Scan/pkg/logger"
	nuclei "github.com/projectdiscovery/nuclei/v3/lib"
	"github.com/projectdiscovery/nuclei/v3/pkg/protocols/common/interactsh"
	"github.com/projectdiscovery/nuclei/v3/pkg/templates"
	"sync"
)

var NucleiEngines []*nuclei.ThreadSafeNucleiEngine
var NucleiEngineWg sync.WaitGroup
var mu sync.Mutex
var Parser *templates.Parser

// NewNucleiEngine creates a thread-safe nuclei engine with update checks
// disabled. Out-of-band (OAST) templates use the interactsh server at
// interactshURL (a URL or comma-separated list; a bare host means https),
// authenticated with interactshToken if set. If interactshURL is empty,
// interactsh is disabled, so ProjectDiscovery's public servers (oast.pro,
// oast.live, ...) are never contacted.
func NewNucleiEngine(interactshURL, interactshToken string) *nuclei.ThreadSafeNucleiEngine {
	mu.Lock()
	defer mu.Unlock()
	if Parser == nil {
		Parser = templates.NewParser()
	}
	// Start from nuclei's defaults (cache size, eviction, poll interval);
	// the SDK fills in the output, progress and issues clients.
	interactshOpts := interactsh.DefaultOptions(nil, nil, nil)
	if interactshURL != "" {
		interactshOpts.ServerURL = interactshURL
		interactshOpts.Authorization = interactshToken
	} else {
		// Same as the nuclei CLI's -no-interactsh: the client never
		// registers with or polls any server, and {{interactsh-url}}
		// markers are left unresolved.
		interactshOpts.NoInteractsh = true
	}
	ctx := context.Background()
	ne, err := nuclei.NewThreadSafeNucleiEngineCtx(ctx, Parser,
		nuclei.DisableUpdateCheck(),
		nuclei.WithInteractshOptions(nuclei.InteractshOpts(*interactshOpts)),
	)
	if err != nil {
		logger.SlogErrorLocal(fmt.Sprintf("NewNucleiEngine error: %v", err))
		return nil
	}
	NucleiEngines = append(NucleiEngines, ne)
	return ne
}

func CloseNucleiEngine() {
	NucleiEngineWg.Wait()
	for _, ne := range NucleiEngines {
		if ne != nil {
			ne.Close()
		}
	}
	Parser = nil
}
