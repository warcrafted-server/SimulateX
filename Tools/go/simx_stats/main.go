// Estadísticas del primer jugador de un RaidSimRequest (protojson), vía
// core.ComputeStats de wowsims: equipo, talentos, buffs, consumibles y final,
// y además las finales con cada hueco de equipo vacío ("withoutSlot"), para
// saber cuánto aporta cada pieza del preset con sus gemas y encantamiento.
// Uso: simx_stats <request.json>  -> JSON por stdout.
// Se compila dentro de Tools/wowsimcli-src (ver Tools/modelo_caps.py).
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/wowsims/wotlk/sim"
	"github.com/wowsims/wotlk/sim/core"
	"github.com/wowsims/wotlk/sim/core/proto"
	"google.golang.org/protobuf/encoding/protojson"
	googleproto "google.golang.org/protobuf/proto"
)

func computeFinal(raid *proto.Raid, encounter *proto.Encounter) ([]float64, error) {
	result := core.ComputeStats(&proto.ComputeStatsRequest{Raid: raid, Encounter: encounter})
	if result.ErrorResult != "" {
		return nil, fmt.Errorf("%s", result.ErrorResult)
	}
	return result.RaidStats.Parties[0].Players[0].FinalStats.GetStats(), nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "uso: simx_stats <request.json>")
		os.Exit(2)
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	request := &proto.RaidSimRequest{}
	if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(data, request); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	sim.RegisterAll()
	result := core.ComputeStats(&proto.ComputeStatsRequest{Raid: request.Raid, Encounter: request.Encounter})
	if result.ErrorResult != "" {
		fmt.Fprintln(os.Stderr, result.ErrorResult)
		os.Exit(1)
	}
	player := result.RaidStats.Parties[0].Players[0]
	out := map[string]interface{}{
		"gear":     player.GearStats.GetStats(),
		"talents":  player.TalentsStats.GetStats(),
		"buffs":    player.BuffsStats.GetStats(),
		"consumes": player.ConsumesStats.GetStats(),
		"final":    player.FinalStats.GetStats(),
	}

	// NewEnvironment puede tocar el proto: cada variante trabaja sobre una copia
	items := request.Raid.Parties[0].Players[0].Equipment.Items
	withoutSlot := make([][]float64, len(items))
	for slot := range items {
		raid := googleproto.Clone(request.Raid).(*proto.Raid)
		raid.Parties[0].Players[0].Equipment.Items[slot] = &proto.ItemSpec{}
		final, err := computeFinal(raid, request.Encounter)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		withoutSlot[slot] = final
	}
	out["withoutSlot"] = withoutSlot
	if err := json.NewEncoder(os.Stdout).Encode(out); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
