export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      player_cards: {
        Row: {
          is_impostor: boolean
          last_chance_options: string[] | null
          player_id: string
          room_id: string
          round_id: string
          word_text: string | null
        }
        Insert: {
          is_impostor: boolean
          last_chance_options?: string[] | null
          player_id: string
          room_id: string
          round_id: string
          word_text?: string | null
        }
        Update: {
          is_impostor?: boolean
          last_chance_options?: string[] | null
          player_id?: string
          room_id?: string
          round_id?: string
          word_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "player_cards_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_cards_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_cards_round_id_fkey"
            columns: ["round_id"]
            isOneToOne: false
            referencedRelation: "rounds"
            referencedColumns: ["id"]
          },
        ]
      }
      players: {
        Row: {
          avatar_color: string
          has_seen_card: boolean
          has_voted: boolean
          id: string
          is_alive: boolean
          joined_at: string
          name: string
          profanity_strikes: number
          room_id: string
          score: number
          user_id: string
        }
        Insert: {
          avatar_color: string
          has_seen_card?: boolean
          has_voted?: boolean
          id?: string
          is_alive?: boolean
          joined_at?: string
          name: string
          profanity_strikes?: number
          room_id: string
          score?: number
          user_id: string
        }
        Update: {
          avatar_color?: string
          has_seen_card?: boolean
          has_voted?: boolean
          id?: string
          is_alive?: boolean
          joined_at?: string
          name?: string
          profanity_strikes?: number
          room_id?: string
          score?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "players_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      profanity_words: {
        Row: {
          word: string
        }
        Insert: {
          word: string
        }
        Update: {
          word?: string
        }
        Relationships: []
      }
      rooms: {
        Row: {
          active_round_id: string | null
          clue_round_starts_at: string | null
          clue_turn_index: number
          code: string
          created_at: string
          discussion_round: number
          eliminated_player_id: string | null
          games_played: number
          guess_deadline: string | null
          host_player_id: string | null
          id: string
          last_vote_tally: Json | null
          outcome: Database["public"]["Enums"]["game_outcome"] | null
          revealed_impostor_id: string | null
          revealed_word: string | null
          status: Database["public"]["Enums"]["room_status"]
          turn_deadline: string | null
          updated_at: string
          votes_cast: number
          voting_cycle: number
        }
        Insert: {
          active_round_id?: string | null
          clue_round_starts_at?: string | null
          clue_turn_index?: number
          code: string
          created_at?: string
          discussion_round?: number
          eliminated_player_id?: string | null
          games_played?: number
          guess_deadline?: string | null
          host_player_id?: string | null
          id?: string
          last_vote_tally?: Json | null
          outcome?: Database["public"]["Enums"]["game_outcome"] | null
          revealed_impostor_id?: string | null
          revealed_word?: string | null
          status?: Database["public"]["Enums"]["room_status"]
          turn_deadline?: string | null
          updated_at?: string
          votes_cast?: number
          voting_cycle?: number
        }
        Update: {
          active_round_id?: string | null
          clue_round_starts_at?: string | null
          clue_turn_index?: number
          code?: string
          created_at?: string
          discussion_round?: number
          eliminated_player_id?: string | null
          games_played?: number
          guess_deadline?: string | null
          host_player_id?: string | null
          id?: string
          last_vote_tally?: Json | null
          outcome?: Database["public"]["Enums"]["game_outcome"] | null
          revealed_impostor_id?: string | null
          revealed_word?: string | null
          status?: Database["public"]["Enums"]["room_status"]
          turn_deadline?: string | null
          updated_at?: string
          votes_cast?: number
          voting_cycle?: number
        }
        Relationships: [
          {
            foreignKeyName: "rooms_active_round_fk"
            columns: ["active_round_id"]
            isOneToOne: false
            referencedRelation: "rounds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rooms_eliminated_player_fk"
            columns: ["eliminated_player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rooms_host_player_fk"
            columns: ["host_player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      round_clues: {
        Row: {
          discussion_round: number
          player_id: string
          round_id: string
          submitted_at: string | null
          timed_out: boolean
          turn_index: number
          word: string | null
        }
        Insert: {
          discussion_round: number
          player_id: string
          round_id: string
          submitted_at?: string | null
          timed_out?: boolean
          turn_index: number
          word?: string | null
        }
        Update: {
          discussion_round?: number
          player_id?: string
          round_id?: string
          submitted_at?: string | null
          timed_out?: boolean
          turn_index?: number
          word?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "round_clues_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "round_clues_round_id_fkey"
            columns: ["round_id"]
            isOneToOne: false
            referencedRelation: "rounds"
            referencedColumns: ["id"]
          },
        ]
      }
      rounds: {
        Row: {
          created_at: string
          id: string
          impostor_player_id: string
          last_chance_word_ids: number[]
          resolved_at: string | null
          room_id: string
          round_number: number
          word_id: number
        }
        Insert: {
          created_at?: string
          id?: string
          impostor_player_id: string
          last_chance_word_ids?: number[]
          resolved_at?: string | null
          room_id: string
          round_number: number
          word_id: number
        }
        Update: {
          created_at?: string
          id?: string
          impostor_player_id?: string
          last_chance_word_ids?: number[]
          resolved_at?: string | null
          room_id?: string
          round_number?: number
          word_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "rounds_impostor_player_id_fkey"
            columns: ["impostor_player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rounds_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rounds_word_id_fkey"
            columns: ["word_id"]
            isOneToOne: false
            referencedRelation: "words"
            referencedColumns: ["id"]
          },
        ]
      }
      votes: {
        Row: {
          created_at: string
          id: string
          room_id: string
          round_id: string
          target_player_id: string | null
          voter_player_id: string
          voting_cycle: number
        }
        Insert: {
          created_at?: string
          id?: string
          room_id: string
          round_id: string
          target_player_id?: string | null
          voter_player_id: string
          voting_cycle: number
        }
        Update: {
          created_at?: string
          id?: string
          room_id?: string
          round_id?: string
          target_player_id?: string | null
          voter_player_id?: string
          voting_cycle?: number
        }
        Relationships: [
          {
            foreignKeyName: "votes_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "votes_round_id_fkey"
            columns: ["round_id"]
            isOneToOne: false
            referencedRelation: "rounds"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "votes_target_player_id_fkey"
            columns: ["target_player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "votes_voter_player_id_fkey"
            columns: ["voter_player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      words: {
        Row: {
          category: Database["public"]["Enums"]["word_category"]
          id: number
          text: string
        }
        Insert: {
          category: Database["public"]["Enums"]["word_category"]
          id?: never
          text: string
        }
        Update: {
          category?: Database["public"]["Enums"]["word_category"]
          id?: never
          text?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      advance_clue_turn: { Args: { p_room_id: string }; Returns: undefined }
      assert_status: {
        Args: {
          p_expected: Database["public"]["Enums"]["room_status"]
          p_room: Database["public"]["Tables"]["rooms"]["Row"]
        }
        Returns: undefined
      }
      begin_clue_round: { Args: { p_room_id: string }; Returns: undefined }
      begin_round: {
        Args: {
          p_force_impostor_id?: string
          p_force_word_id?: number
          p_room_id: string
        }
        Returns: string
      }
      cast_vote: {
        Args: { p_room_id: string; p_target_player_id?: string }
        Returns: undefined
      }
      close_room: { Args: { p_room_id: string }; Returns: undefined }
      clue_turn_seconds: { Args: { p_turn_index: number }; Returns: number }
      clue_turns_done: { Args: { p_room_id: string }; Returns: boolean }
      confirm_word_seen: { Args: { p_room_id: string }; Returns: undefined }
      create_room: { Args: { p_name: string }; Returns: Json }
      current_player: {
        Args: { p_room_id: string }
        Returns: {
          avatar_color: string
          has_seen_card: boolean
          has_voted: boolean
          id: string
          is_alive: boolean
          joined_at: string
          name: string
          profanity_strikes: number
          room_id: string
          score: number
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "players"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      expire_clue_turn: { Args: { p_room_id: string }; Returns: undefined }
      expire_last_chance: { Args: { p_room_id: string }; Returns: undefined }
      finish_game: {
        Args: {
          p_eliminated?: string
          p_outcome: Database["public"]["Enums"]["game_outcome"]
          p_room_id: string
        }
        Returns: undefined
      }
      gen_room_code: { Args: never; Returns: string }
      impostor_weight: {
        Args: { p_player_id: string; p_room_id: string; p_round_number: number }
        Returns: number
      }
      is_profane: { Args: { p_word: string }; Returns: boolean }
      is_room_member: { Args: { p_room_id: string }; Returns: boolean }
      is_valid_clue: { Args: { p_word: string }; Returns: boolean }
      join_room: { Args: { p_code: string; p_name: string }; Returns: Json }
      kick_player: {
        Args: { p_player_id: string; p_room_id: string }
        Returns: undefined
      }
      leave_room: { Args: { p_room_id: string }; Returns: undefined }
      next_clue_round: { Args: { p_room_id: string }; Returns: undefined }
      normalize_word: { Args: { p_word: string }; Returns: string }
      open_voting: { Args: { p_room_id: string }; Returns: undefined }
      owns_player: { Args: { p_player_id: string }; Returns: boolean }
      pick_avatar_color: { Args: { p_room_id: string }; Returns: string }
      play_again: {
        Args: {
          p_force_impostor_id?: string
          p_force_word_id?: number
          p_room_id: string
        }
        Returns: undefined
      }
      require_uid: { Args: never; Returns: string }
      resolve_voting: { Args: { p_room_id: string }; Returns: undefined }
      start_clue_round_now: { Args: { p_room_id: string }; Returns: undefined }
      start_game: {
        Args: {
          p_force_impostor_id?: string
          p_force_word_id?: number
          p_room_id: string
        }
        Returns: undefined
      }
      submit_clue: {
        Args: { p_room_id: string; p_word: string }
        Returns: Json
      }
      submit_impostor_guess: {
        Args: { p_room_id: string; p_word_text: string }
        Returns: Json
      }
    }
    Enums: {
      game_outcome: "TRUTHERS_WIN" | "IMPOSTOR_WIN" | "IMPOSTOR_STEAL"
      room_status:
        | "LOBBY"
        | "WORD_REVEAL"
        | "DISCUSSION"
        | "VOTING"
        | "LAST_CHANCE"
        | "GAME_OVER"
        | "CLOSED"
      word_category:
        | "LUGARES"
        | "COMIDAS"
        | "ANIMAIS"
        | "PROFISSOES"
        | "OBJETOS"
        | "TECH"
        | "ESPORTES"
        | "CULTURA_POP"
        | "TRANSPORTES"
        | "EVENTOS"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      game_outcome: ["TRUTHERS_WIN", "IMPOSTOR_WIN", "IMPOSTOR_STEAL"],
      room_status: [
        "LOBBY",
        "WORD_REVEAL",
        "DISCUSSION",
        "VOTING",
        "LAST_CHANCE",
        "GAME_OVER",
        "CLOSED",
      ],
      word_category: [
        "LUGARES",
        "COMIDAS",
        "ANIMAIS",
        "PROFISSOES",
        "OBJETOS",
        "TECH",
        "ESPORTES",
        "CULTURA_POP",
        "TRANSPORTES",
        "EVENTOS",
      ],
    },
  },
} as const

