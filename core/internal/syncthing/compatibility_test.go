package syncthing

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestActiveVersionCompatibilityFixtures(t *testing.T) {
	versions := []string{"v1.29", "v2.1"}
	for _, version := range versions {
		t.Run(version, func(t *testing.T) {
			statusContents, err := os.ReadFile(filepath.Join("testdata", version,
				"folder-status.json"))
			if err != nil {
				t.Fatal(err)
			}
			var status FolderStatus
			if err := json.Unmarshal(statusContents, &status); err != nil {
				t.Fatal(err)
			}
			if status.State == "" || status.GlobalFiles == 0 {
				t.Fatalf("fixture lost required folder state: %#v", status)
			}

			eventContents, err := os.ReadFile(filepath.Join("testdata", version,
				"events.json"))
			if err != nil {
				t.Fatal(err)
			}
			var events []Event
			if err := json.Unmarshal(eventContents, &events); err != nil {
				t.Fatal(err)
			}
			if len(events) != 1 || events[0].ID == 0 || len(events[0].Data) == 0 {
				t.Fatalf("fixture lost required event state: %#v", events)
			}
		})
	}
}

func FuzzEventJSON(f *testing.F) {
	f.Add([]byte(`[{"id":1,"type":"ConfigSaved","data":{}}]`))
	f.Add([]byte(`null`))
	f.Fuzz(func(t *testing.T, contents []byte) {
		var events []Event
		_ = json.Unmarshal(contents, &events)
	})
}
