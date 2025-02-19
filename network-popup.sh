#!/bin/bash

# Récupérer la position de la souris
eval "$(xdotool getmouselocation --shell)"
X_POPUP=$X
Y_POPUP=$((Y + 15))

# Récupérer la résolution de l'écran
SCREEN_WIDTH=$(xrandr | grep '*' | awk '{print $1}' | cut -d 'x' -f1)
SCREEN_HEIGHT=$(xrandr | grep '*' | awk '{print $1}' | cut -d 'x' -f2)

# Définir la taille de la fenêtre YAD
WINDOW_WIDTH=600
WINDOW_HEIGHT=400

# Ajuster X_POPUP si la fenêtre dépasse à droite
if (( X_POPUP + WINDOW_WIDTH > SCREEN_WIDTH )); then
    X_POPUP=$((SCREEN_WIDTH - WINDOW_WIDTH))
fi

# Ajuster Y_POPUP si la fenêtre dépasse en bas
if (( Y_POPUP + WINDOW_HEIGHT > SCREEN_HEIGHT )); then
    Y_POPUP=$((SCREEN_HEIGHT - WINDOW_HEIGHT))
fi

# S'assurer que X_POPUP et Y_POPUP restent positifs
X_POPUP=$(( X_POPUP < 0 ? 0 : X_POPUP ))
Y_POPUP=$(( Y_POPUP < 0 ? 0 : Y_POPUP ))

# Affichage d'un pop-up temporaire pendant la recherche des réseaux
(yad --class=network_popup --geometry=+${X_POPUP}+${Y_POPUP} \
     --title="Recherche Wi-Fi" \
     --text="Recherche en cours..." \
     --no-buttons --no-escape --on-top) &
POPUP_PID=$!

# Fonction pour récupérer la liste des réseaux Wi-Fi dans un tableau Bash
get_wifi_list() {
    wifi_list=()
    while IFS='|' read -r in_use ssid signal bars security; do
        # Définition des couleurs en fonction de la puissance du signal
        if (( signal >= 75 )); then
            color_signal="<span foreground='green'><b>$signal</b></span>"
        elif (( signal >= 50 )); then
            color_signal="<span foreground='orange'><b>$signal</b></span>"
        else
            color_signal="<span foreground='red'><b>$signal</b></span>"
        fi

        # Définition des couleurs en fonction des barres du signal
        case "$bars" in
            "▂▄▆█")  color_bars="<span foreground='green'><b>$bars</b></span>" ;; # Fort
            "▂▄▆_")  color_bars="<span foreground='orange'><b>$bars</b></span>" ;; # Moyen
            "▂▄__")  color_bars="<span foreground='red'><b>$bars</b></span>" ;; # Faible
            *)       color_bars="$bars" ;;
        esac

        wifi_list+=( "$in_use" "$ssid" "$color_signal" "$color_bars" "$security" )
    done < <(
        # Récupère et filitre les réseaux disponible
        nmcli -t -f IN-USE,SSID,SIGNAL,BARS,SECURITY device wifi list | \
        awk -F: '
        {
            if ($1 == "") {
                in_use   = "\u00A0";
                ssid     = $2;
                signal   = $3;
                bars     = $4;
                security = ($5 == "" ? "--" : $5);
            } else {
                in_use   = ($1 == "*") ? "✔" : "\u00A0";
                ssid     = $2;
                signal   = $3;
                bars     = $4;
                security = ($5 == "" ? "--" : $5);
            }
            if (length(ssid) > 0) { # Ajouter && !seen[ssid]++ si on veut enlever les doublons
                print in_use "|" ssid "|" signal "|" bars "|" security
            }
        }'
    )
}

# Exécuter la récupération de la liste des réseaux Wi-Fi
get_wifi_list

# Fermer le pop-up dès que nmcli a terminé
kill $POPUP_PID 2>/dev/null

# Boucle principale d'affichage et d'interaction
while true; do
    # Afficher la liste dans YAD et récupérer le SSID sélectionné
    selected_ssid=$(yad --list \
        --class=network_popup \
        --title="Sélectionner un réseau Wi-Fi" \
        --geometry=${WINDOW_WIDTH}x${WINDOW_HEIGHT}+${X_POPUP}+${Y_POPUP} \
        --column="Connecté" \
        --column="SSID" \
        --column="Signal" \
        --column="Force" \
        --column="Sécurité" \
        --separator=" " \
        --ontop \
        --button="Se connecter":2 \
        --button="Actualiser":1 \
        --button="Fermer":0 \
        --print-column=2 \
        --dclick-action="bash -c 'exit 2'" \
        -- "${wifi_list[@]}")
    
    case $? in
        0)  # Fermer
            exit 0
            ;;
        1)  # Actualiser la liste
            get_wifi_list
            continue
            ;;
        2)  # Se connecter
            if [[ -n "$selected_ssid" ]]; then
                SELECTED_SSID=$(echo "$selected_ssid" | sed 's/ *$//') # Un espace se rajoute automatiquement à la fin donc on l'enlève
                if [[ -n "$SELECTED_SSID" ]]; then
                    # Vérifier si le réseau est déjà enregistré
                    if nmcli connection show "$SELECTED_SSID" &>/dev/null; then
                        nmcli connection up "$SELECTED_SSID"
                    else
                        # Vérifier si le réseau est sécurisé
                        SECURITY_TYPE=$(nmcli -t -f SSID,SECURITY device wifi list | \
                            awk -F: -v ssid="$SELECTED_SSID" '$1 == ssid {print $2}')
                        if [[ -z "$SECURITY_TYPE" || "$SECURITY_TYPE" == "--" ]]; then
                            # Connexion à un réseau ouvert
                            nmcli device wifi connect "$SELECTED_SSID"
                        else
                            # Demander le mot de passe
                            PASSWORD=$(yad --class=network_popup --geometry=+${X_POPUP}+${Y_POPUP} \
                                --entry --title="Connexion Wi-Fi" \
                                --text="Entrez le mot de passe pour \"$SELECTED_SSID\"" \
                                --hide-text)
                            if [[ -n "$PASSWORD" ]]; then
                                nmcli device wifi connect "$SELECTED_SSID" password "$PASSWORD"
                            fi
                        fi
                    fi
                fi
            fi
            # Actualiser la liste après une tentative de connexion
            get_wifi_list
            ;;
        *)
            exit 0
            ;;
    esac
done
