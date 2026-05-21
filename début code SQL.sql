SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."categorie" AS ENUM (
    'Fosse',
    'Cat1',
    'Cat2',
    'Cat3',
    'VIP'
);


ALTER TYPE "public"."categorie" OWNER TO "postgres";


CREATE TYPE "public"."statut" AS ENUM (
    'Disponible',
    'Complète',
    'Annulée',
    'Passée'
);


ALTER TYPE "public"."statut" OWNER TO "postgres";


CREATE TYPE "public"."statut_fid" AS ENUM (
    'Standard',
    'Premium'
);


ALTER TYPE "public"."statut_fid" OWNER TO "postgres";


CREATE TYPE "public"."statut_rembours" AS ENUM (
    'Demande',
    'En_cours',
    'Effectué'
);


ALTER TYPE "public"."statut_rembours" OWNER TO "postgres";


CREATE TYPE "public"."type_even" AS ENUM (
    'Sportif',
    'Concert',
    'Spectacle',
    'Festival'
);


ALTER TYPE "public"."type_even" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_appliquer_reduction_parrainage"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_id_parrain VARCHAR;
BEGIN
    -- On cherche si le client qui effectue le paiement a un parrain [cite: 35]
    SELECT id_parrain INTO v_id_parrain FROM public.client WHERE id_client = NEW.id_client;

    -- Si un parrain existe, on réduit le montant de 10% [cite: 24, 32]
    IF v_id_parrain IS NOT NULL THEN
        NEW.montant := NEW.montant * 0.90;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_appliquer_reduction_parrainage"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_assigner_rang_attente"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- On cherche le dernier rang actuel pour cette séance et on fait +1
    SELECT COALESCE(MAX(rang), 0) + 1 INTO NEW.rang 
    FROM public.personnes_en_attente 
    WHERE id_seance = NEW.id_seance;
    
    -- On s'assure que la date d'inscription est bien maintenant [cite: 41]
    NEW.date_inscrip := NOW();
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_assigner_rang_attente"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_check_annulation_30"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_capacite INT;
    v_vendus INT;
    v_ratio FLOAT;
BEGIN
    -- Récupération de la capacité prévue pour la séance
    SELECT capacite_seance INTO v_capacite FROM public.seance WHERE id_seance = NEW.id_seance;
    
    -- Calcul du nombre de billets déjà réservés
    SELECT COUNT(*) INTO v_vendus FROM public.billet WHERE id_seance = NEW.id_seance;
    
    -- Calcul du ratio (on ajoute 1 pour inclure le billet en cours d'insertion)
    v_ratio := ((v_vendus + 1)::FLOAT / v_capacite::FLOAT) * 100;

    -- Si on est proche de l'événement (ex: moins de 5 jours avant) et < 30%
    -- On met à jour le statut en 'annulé' 
    IF v_ratio < 30.0 AND (SELECT date_seance FROM public.seance WHERE id_seance = NEW.id_seance) <= (CURRENT_DATE + INTERVAL '5 days') THEN
        UPDATE public.seance SET statut_seance = 'annulé' WHERE id_seance = NEW.id_seance;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_check_annulation_30"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_verifier_seance_complete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_max INT;
    v_actuel INT;
BEGIN
    SELECT capacite_seance INTO v_max FROM public.seance WHERE id_seance = NEW.id_seance;
    SELECT COUNT(*) INTO v_actuel FROM public.billet WHERE id_seance = NEW.id_seance;

    IF v_actuel + 1 >= v_max THEN
        UPDATE public.seance SET statut_seance = 'complet' WHERE id_seance = NEW.id_seance;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fn_verifier_seance_complete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."billet" (
    "code_reserv" character varying NOT NULL,
    "code_barre" character varying NOT NULL,
    "place" character varying NOT NULL,
    "categorie" "public"."categorie" NOT NULL,
    "id_seance" character varying NOT NULL,
    "num_paiement" character varying NOT NULL,
    "id_client" character varying NOT NULL
);


ALTER TABLE "public"."billet" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."client" (
    "id_client" character varying NOT NULL,
    "nom" character varying NOT NULL,
    "prenom" character varying NOT NULL,
    "mail" character varying NOT NULL,
    "tel" character varying,
    "date_inscrip" "date" NOT NULL,
    "statut_fid" "public"."statut_fid" NOT NULL,
    "id_parrain" character varying NOT NULL,
    CONSTRAINT "check_date_inscription" CHECK (("date_inscrip" <= CURRENT_DATE))
);


ALTER TABLE "public"."client" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."evenement" (
    "id_even" character varying NOT NULL,
    "nom_even" character varying NOT NULL,
    "description" "text" NOT NULL,
    "debut_even" "date" NOT NULL,
    "fin_even" "date" NOT NULL,
    "affiche_even" "bytea" NOT NULL,
    "type_even" "public"."type_even" NOT NULL,
    CONSTRAINT "check_even_dates" CHECK (("fin_even" >= "debut_even")),
    CONSTRAINT "check_even_future" CHECK (("debut_even" > CURRENT_DATE))
);


ALTER TABLE "public"."evenement" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."paiement" (
    "num_paiement" character varying NOT NULL,
    "montant" real NOT NULL,
    "intitule" character varying NOT NULL
);


ALTER TABLE "public"."paiement" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."performe" (
    "id_perform" character varying NOT NULL,
    "id_even" character varying NOT NULL
);


ALTER TABLE "public"."performe" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."performer" (
    "id_perform" character varying NOT NULL,
    "nom_scene" character varying NOT NULL,
    "nom" character varying NOT NULL,
    "prenom" character varying NOT NULL,
    "date_naiss" "date" NOT NULL,
    "nationalite" character varying,
    "biographie" "text",
    CONSTRAINT "check_date_naissance" CHECK ((("date_naiss" > '1900-01-01'::"date") AND ("date_naiss" < CURRENT_DATE)))
);


ALTER TABLE "public"."performer" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."personnes_en_attente" (
    "code_file_attente" character varying NOT NULL,
    "date_inscrip" timestamp with time zone NOT NULL,
    "rang" integer NOT NULL,
    "id_seance" character varying NOT NULL,
    "id_client" character varying NOT NULL,
    CONSTRAINT "check_rang_positif" CHECK (("rang" >= 0))
);


ALTER TABLE "public"."personnes_en_attente" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."remboursement" (
    "code_rembours" character varying NOT NULL,
    "motif" character varying NOT NULL,
    "statut_rembours" "public"."statut_rembours" NOT NULL
);


ALTER TABLE "public"."remboursement" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."salle" (
    "id_salle" character varying NOT NULL,
    "nom" character varying NOT NULL,
    "capacite_max" integer NOT NULL,
    "adresse" "text" NOT NULL,
    "plan_salle" "bytea" NOT NULL,
    CONSTRAINT "check_capacite_max" CHECK ((("capacite_max" > 0) AND ("capacite_max" <= 1000000)))
);


ALTER TABLE "public"."salle" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."seance" (
    "id_seance" character varying NOT NULL,
    "date_seance" "date" NOT NULL,
    "heure_deb" time without time zone NOT NULL,
    "heure_fin" time without time zone NOT NULL,
    "statut_seance" "public"."statut" NOT NULL,
    "capacite_seance" integer NOT NULL,
    "id_tarif" character varying NOT NULL,
    "id_even" character varying NOT NULL,
    "id_salle" character varying NOT NULL,
    CONSTRAINT "Seance_capacite_seance_check" CHECK (("capacite_seance" > 0)),
    CONSTRAINT "check_capacite_seance" CHECK ((("capacite_seance" > 0) AND ("capacite_seance" <= 1000000))),
    CONSTRAINT "check_seance_dates" CHECK (("date_seance" < '2999-01-01'::"date")),
    CONSTRAINT "check_seance_times" CHECK (("heure_fin" > "heure_deb"))
);


ALTER TABLE "public"."seance" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tarif" (
    "id_tarif" character varying NOT NULL,
    "prix_fosse" real,
    "prix_vip" real,
    "prix_cat1" real,
    "prix_cat2" real,
    "prix_cat3" real,
    CONSTRAINT "check_prix_vip_max" CHECK ((("prix_vip" >= "prix_fosse") AND ("prix_vip" >= "prix_cat1") AND ("prix_vip" >= "prix_cat2") AND ("prix_vip" >= "prix_cat3")))
);


ALTER TABLE "public"."tarif" OWNER TO "postgres";


ALTER TABLE ONLY "public"."billet"
    ADD CONSTRAINT "Billet_pkey" PRIMARY KEY ("code_reserv");



ALTER TABLE ONLY "public"."client"
    ADD CONSTRAINT "Client_pkey" PRIMARY KEY ("id_client");



ALTER TABLE ONLY "public"."evenement"
    ADD CONSTRAINT "Evenement_pkey" PRIMARY KEY ("id_even");



ALTER TABLE ONLY "public"."paiement"
    ADD CONSTRAINT "Paiement_pkey" PRIMARY KEY ("num_paiement");



ALTER TABLE ONLY "public"."performe"
    ADD CONSTRAINT "Performe_pkey" PRIMARY KEY ("id_perform", "id_even");



ALTER TABLE ONLY "public"."performer"
    ADD CONSTRAINT "Performer_pkey" PRIMARY KEY ("id_perform");



ALTER TABLE ONLY "public"."personnes_en_attente"
    ADD CONSTRAINT "Personnes en attente_pkey" PRIMARY KEY ("code_file_attente");



ALTER TABLE ONLY "public"."remboursement"
    ADD CONSTRAINT "Remboursement_pkey" PRIMARY KEY ("code_rembours");



ALTER TABLE ONLY "public"."salle"
    ADD CONSTRAINT "Salle_pkey" PRIMARY KEY ("id_salle");



ALTER TABLE ONLY "public"."seance"
    ADD CONSTRAINT "Seance_pkey" PRIMARY KEY ("id_seance");



ALTER TABLE ONLY "public"."tarif"
    ADD CONSTRAINT "Tarif_pkey" PRIMARY KEY ("id_tarif");



CREATE OR REPLACE TRIGGER "tr_check_annulation_auto" AFTER INSERT ON "public"."billet" FOR EACH ROW EXECUTE FUNCTION "public"."fn_check_annulation_30"();



CREATE OR REPLACE TRIGGER "tr_reduction_parrainage" BEFORE INSERT ON "public"."paiement" FOR EACH ROW EXECUTE FUNCTION "public"."fn_appliquer_reduction_parrainage"();



CREATE OR REPLACE TRIGGER "tr_seance_complete" BEFORE INSERT ON "public"."billet" FOR EACH ROW EXECUTE FUNCTION "public"."fn_verifier_seance_complete"();



CREATE OR REPLACE TRIGGER "tr_set_rang_automatique" BEFORE INSERT ON "public"."personnes_en_attente" FOR EACH ROW EXECUTE FUNCTION "public"."fn_assigner_rang_attente"();



ALTER TABLE ONLY "public"."billet"
    ADD CONSTRAINT "Billet_id_client_fkey" FOREIGN KEY ("id_client") REFERENCES "public"."client"("id_client");



ALTER TABLE ONLY "public"."billet"
    ADD CONSTRAINT "Billet_id_seance_fkey" FOREIGN KEY ("id_seance") REFERENCES "public"."seance"("id_seance");



ALTER TABLE ONLY "public"."billet"
    ADD CONSTRAINT "Billet_num_paiement_fkey" FOREIGN KEY ("num_paiement") REFERENCES "public"."paiement"("num_paiement");



ALTER TABLE ONLY "public"."performe"
    ADD CONSTRAINT "Performe_id_even_fkey" FOREIGN KEY ("id_even") REFERENCES "public"."evenement"("id_even");



ALTER TABLE ONLY "public"."performe"
    ADD CONSTRAINT "Performe_id_perform_fkey" FOREIGN KEY ("id_perform") REFERENCES "public"."performer"("id_perform");



ALTER TABLE ONLY "public"."personnes_en_attente"
    ADD CONSTRAINT "Personnes en attente_id_client_fkey" FOREIGN KEY ("id_client") REFERENCES "public"."client"("id_client");



ALTER TABLE ONLY "public"."personnes_en_attente"
    ADD CONSTRAINT "Personnes en attente_id_seance_fkey" FOREIGN KEY ("id_seance") REFERENCES "public"."seance"("id_seance");



ALTER TABLE ONLY "public"."remboursement"
    ADD CONSTRAINT "Remboursement_code_rembours_fkey" FOREIGN KEY ("code_rembours") REFERENCES "public"."paiement"("num_paiement");



ALTER TABLE ONLY "public"."seance"
    ADD CONSTRAINT "Seance_id_even_fkey" FOREIGN KEY ("id_even") REFERENCES "public"."evenement"("id_even");



ALTER TABLE ONLY "public"."seance"
    ADD CONSTRAINT "Seance_id_salle_fkey" FOREIGN KEY ("id_salle") REFERENCES "public"."salle"("id_salle");



ALTER TABLE ONLY "public"."seance"
    ADD CONSTRAINT "Seance_id_tarif_fkey" FOREIGN KEY ("id_tarif") REFERENCES "public"."tarif"("id_tarif");



ALTER TABLE ONLY "public"."client"
    ADD CONSTRAINT "client_id_parrain_fkey" FOREIGN KEY ("id_parrain") REFERENCES "public"."client"("id_client");



ALTER TABLE "public"."billet" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."client" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."evenement" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."paiement" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."performe" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."performer" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."personnes_en_attente" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."remboursement" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."salle" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."seance" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tarif" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";


GRANT ALL ON FUNCTION "public"."fn_appliquer_reduction_parrainage"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_appliquer_reduction_parrainage"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_appliquer_reduction_parrainage"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_assigner_rang_attente"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_assigner_rang_attente"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_assigner_rang_attente"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_check_annulation_30"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_check_annulation_30"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_check_annulation_30"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_verifier_seance_complete"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_verifier_seance_complete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_verifier_seance_complete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";


















GRANT ALL ON TABLE "public"."billet" TO "anon";
GRANT ALL ON TABLE "public"."billet" TO "authenticated";
GRANT ALL ON TABLE "public"."billet" TO "service_role";



GRANT ALL ON TABLE "public"."client" TO "anon";
GRANT ALL ON TABLE "public"."client" TO "authenticated";
GRANT ALL ON TABLE "public"."client" TO "service_role";



GRANT ALL ON TABLE "public"."evenement" TO "anon";
GRANT ALL ON TABLE "public"."evenement" TO "authenticated";
GRANT ALL ON TABLE "public"."evenement" TO "service_role";



GRANT ALL ON TABLE "public"."paiement" TO "anon";
GRANT ALL ON TABLE "public"."paiement" TO "authenticated";
GRANT ALL ON TABLE "public"."paiement" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."performe" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."performe" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."performe" TO "service_role";



GRANT ALL ON TABLE "public"."performer" TO "anon";
GRANT ALL ON TABLE "public"."performer" TO "authenticated";
GRANT ALL ON TABLE "public"."performer" TO "service_role";



GRANT ALL ON TABLE "public"."personnes_en_attente" TO "anon";
GRANT ALL ON TABLE "public"."personnes_en_attente" TO "authenticated";
GRANT ALL ON TABLE "public"."personnes_en_attente" TO "service_role";



GRANT ALL ON TABLE "public"."remboursement" TO "anon";
GRANT ALL ON TABLE "public"."remboursement" TO "authenticated";
GRANT ALL ON TABLE "public"."remboursement" TO "service_role";



GRANT ALL ON TABLE "public"."salle" TO "anon";
GRANT ALL ON TABLE "public"."salle" TO "authenticated";
GRANT ALL ON TABLE "public"."salle" TO "service_role";



GRANT ALL ON TABLE "public"."seance" TO "anon";
GRANT ALL ON TABLE "public"."seance" TO "authenticated";
GRANT ALL ON TABLE "public"."seance" TO "service_role";



GRANT ALL ON TABLE "public"."tarif" TO "anon";
GRANT ALL ON TABLE "public"."tarif" TO "authenticated";
GRANT ALL ON TABLE "public"."tarif" TO "service_role";




ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";


INSERT INTO "public"."client" ("id_client", "nom", "prenom", "mail", "tel", "date_inscrip", "statut_fid", "id_parrain") 
    VALUES ('C-01', 'Martin', 'Lucas', 'l.martin@email.com', '0601020304', '2024-01-01', 'Premium', 'C-01'), ('C-02', 'Bernard', 'Chloe', 'c.bernard@email.com', '0611223344', '2024-01-05', 'Standard', 'C-01'), ('C-03', 'Thomas', 'Hugo', 'h.thomas@email.com', '0622334455', '2024-01-10', 'Standard', 'C-01'), ('C-04', 'Petit', 'Emma', 'e.petit@email.com', '0633445566', '2024-01-12', 'Premium', 'C-01'), ('C-05', 'Robert', 'Leo', 'l.robert@email.com', '0644556677', '2024-01-15', 'Standard', 'C-01'), ('C-06', 'Richard', 'Jade', 'j.richard@email.com', '0655667788', '2024-01-20', 'Standard', 'C-01'), ('C-07', 'Durand', 'Nathan', 'n.durand@email.com', '0666778899', '2024-01-25', 'Premium', 'C-01'), ('C-08', 'Dubois', 'Alice', 'a.dubois@email.com', '0677889900', '2024-02-01', 'Standard', 'C-01'), ('C-09', 'Moreau', 'Enzo', 'e.moreau@email.com', '0688990011', '2024-02-05', 'Standard', 'C-01'), ('C-10', 'Laurent', 'Lina', 'l.laurent@email.com', '0699001122', '2024-02-10', 'Premium', 'C-01'), ('C-11', 'Simon', 'Adam', 'a.simon@email.com', '0701020304', '2024-02-15', 'Standard', 'C-01'), ('C-12', 'Michel', 'Manon', 'm.michel@email.com', '0711223344', '2024-02-20', 'Standard', 'C-01'), ('C-13', 'Lefebvre', 'Louis', 'l.lefebvre@email.com', '0722334455', '2024-02-25', 'Premium', 'C-01'), ('C-14', 'Leroy', 'Zoe', 'z.leroy@email.com', '0733445566', '2024-03-01', 'Standard', 'C-01'), ('C-15', 'Roux', 'Maelys', 'm.roux@email.com', '0744556677', '2024-03-05', 'Standard', 'C-01'), ('C-16', 'David', 'Arthur', 'a.david@email.com', '0755667788', '2024-03-10', 'Premium', 'C-01'), ('C-17', 'Bertrand', 'Mila', 'b.mila@email.com', '0766778899', '2024-03-15', 'Standard', 'C-01'), ('C-18', 'Morel', 'Gabriel', 'm.gabriel@email.com', '0777889900', '2024-03-20', 'Standard', 'C-01'), ('C-19', 'Fournier', 'Rose', 'f.rose@email.com', '0788990011', '2024-03-25', 'Premium', 'C-01'), ('C-20', 'Girard', 'Jules', 'g.jules@email.com', '0799001122', '2024-03-30', 'Standard', 'C-01');

INSERT INTO "public"."billet" ("code_reserv", "code_barre", "place", "categorie", "id_seance", "num_paiement", "id_client") 
    VALUES ('RES-01', 'BC-01', 'A-01', 'Cat1', 'SEA-01', 'PAY-01', 'C-01'), ('RES-02', 'BC-02', 'Fosse-10', 'Fosse', 'SEA-02', 'PAY-02', 'C-02'), ('RES-03', 'BC-03', 'B-22', 'Cat1', 'SEA-03', 'PAY-03', 'C-03'), ('RES-04', 'BC-04', 'C-15', 'Cat1', 'SEA-04', 'PAY-04', 'C-04'), ('RES-05', 'BC-05', 'VIP-01', 'VIP', 'SEA-05', 'PAY-05', 'C-05'), ('RES-06', 'BC-06', 'Fosse-05', 'Fosse', 'SEA-06', 'PAY-06', 'C-06'), ('RES-07', 'BC-07', 'A-50', 'Cat1', 'SEA-07', 'PAY-07', 'C-07'), ('RES-08', 'BC-08', 'D-02', 'Cat2', 'SEA-08', 'PAY-08', 'C-08'), ('RES-09', 'BC-09', 'Fosse-99', 'Fosse', 'SEA-09', 'PAY-09', 'C-09'), ('RES-10', 'BC-10', 'B-05', 'Cat1', 'SEA-10', 'PAY-10', 'C-10'), ('RES-11', 'BC-11', 'C-12', 'Cat1', 'SEA-11', 'PAY-11', 'C-11'), ('RES-12', 'BC-12', 'E-10', 'Cat3', 'SEA-12', 'PAY-12', 'C-12'), ('RES-13', 'BC-13', 'A-08', 'Cat1', 'SEA-13', 'PAY-13', 'C-13'), ('RES-14', 'BC-14', 'Fosse-20', 'Fosse', 'SEA-14', 'PAY-14', 'C-14'), ('RES-15', 'BC-15', 'VIP-10', 'VIP', 'SEA-15', 'PAY-15', 'C-15'), ('RES-16', 'BC-16', 'B-40', 'Cat1', 'SEA-16', 'PAY-16', 'C-16'), ('RES-17', 'BC-17', 'D-15', 'Cat2', 'SEA-17', 'PAY-17', 'C-17'), ('RES-18', 'BC-18', 'A-100', 'Cat1', 'SEA-18', 'PAY-18', 'C-18'), ('RES-19', 'BC-19', 'Fosse-01', 'Fosse', 'SEA-19', 'PAY-19', 'C-19'), ('RES-20', 'BC-20', 'B-12', 'Cat1', 'SEA-20', 'PAY-20', 'C-20');

INSERT INTO "public"."evenement" ("id_even", "nom_even", "description", "debut_even", "fin_even", "affiche_even", "type_even") 
    VALUES ('E-01', 'Rock Tour', 'Tournee rock', '2026-06-01', '2026-06-15', '{"type":"Buffer","data":[105,109,103,49]}', 'Concert'), ('E-02', 'Jazz Night', 'Soiree Jazz', '2026-07-10', '2026-07-10', '{"type":"Buffer","data":[105,109,103,50]}', 'Concert'), ('E-03', 'Humour 2026', 'Stand up', '2026-08-05', '2026-08-05', '{"type":"Buffer","data":[105,109,103,51]}', 'Spectacle'), ('E-04', 'Pop Star', 'Show pop', '2026-09-12', '2026-09-15', '{"type":"Buffer","data":[105,109,103,52]}', 'Concert'), ('E-05', 'Magic Show', 'Magie moderne', '2026-10-01', '2026-10-02', '{"type":"Buffer","data":[105,109,103,53]}', 'Spectacle'), ('E-06', 'Electro Fest', 'Musique electro', '2026-06-20', '2026-06-22', '{"type":"Buffer","data":[105,109,103,54]}', 'Festival'), ('E-07', 'Metal Blast', 'Heavy metal', '2026-11-15', '2026-11-15', '{"type":"Buffer","data":[105,109,103,55]}', 'Concert'), ('E-08', 'Classical Gala', 'Opera', '2026-12-20', '2026-12-20', '{"type":"Buffer","data":[105,109,103,56]}', 'Spectacle'), ('E-09', 'Indie Folk', 'Musique folk', '2026-06-05', '2026-06-05', '{"type":"Buffer","data":[105,109,103,57]}', 'Concert'), ('E-10', 'Rap Battle', 'Hip hop event', '2026-07-25', '2026-07-25', '{"type":"Buffer","data":[105,109,103,49,48]}', 'Concert'), ('E-11', 'Dance Mania', 'Show danse', '2026-08-20', '2026-08-20', '{"type":"Buffer","data":[105,109,103,49,49]}', 'Spectacle'), ('E-12', 'Blues Road', 'Concert blues', '2026-09-01', '2026-09-01', '{"type":"Buffer","data":[105,109,103,49,50]}', 'Concert'), ('E-13', 'Kids Show', 'Spectacle enfant', '2026-10-15', '2026-10-15', '{"type":"Buffer","data":[105,109,103,49,51]}', 'Spectacle'), ('E-14', 'Reggae Sun', 'Summer reggae', '2026-07-05', '2026-07-05', '{"type":"Buffer","data":[105,109,103,49,52]}', 'Concert'), ('E-15', 'Piano Solo', 'Recital piano', '2026-11-05', '2026-11-05', '{"type":"Buffer","data":[105,109,103,49,53]}', 'Concert'), ('E-16', 'Techno Rave', 'Soiree techno', '2026-12-31', '2027-01-01', '{"type":"Buffer","data":[105,109,103,49,54]}', 'Festival'), ('E-17', 'Soul Train', 'Musique soul', '2026-10-25', '2026-10-25', '{"type":"Buffer","data":[105,109,103,49,55]}', 'Concert'), ('E-18', 'Circus Gala', 'Nouveau cirque', '2026-12-10', '2026-12-15', '{"type":"Buffer","data":[105,109,103,49,56]}', 'Spectacle'), ('E-19', 'Punk Spirit', 'Rock punk', '2026-08-28', '2026-08-28', '{"type":"Buffer","data":[105,109,103,49,57]}', 'Concert'), ('E-20', 'Latin Dance', 'Salsa night', '2026-09-30', '2026-09-30', '{"type":"Buffer","data":[105,109,103,50,48]}', 'Spectacle');

INSERT INTO "public"."paiement" ("num_paiement", "montant", "intitule") 
    VALUES ('PAY-01', 85, 'Achat Rock Tour'), ('PAY-02', 30, 'Achat Jazz Night'), ('PAY-03', 95, 'Achat Humour 2026'), ('PAY-04', 70, 'Achat Pop Star'), ('PAY-05', 90, 'Achat Magic Show'), ('PAY-06', 35, 'Achat Electro Fest'), ('PAY-07', 110, 'Achat Metal Blast'), ('PAY-08', 50, 'Achat Classical Gala'), ('PAY-09', 130, 'Achat Indie Folk'), ('PAY-10', 88, 'Achat Rap Battle'), ('PAY-11', 82, 'Achat Dance Mania'), ('PAY-12', 78, 'Achat Blues Road'), ('PAY-13', 92, 'Achat Kids Show'), ('PAY-14', 62, 'Achat Reggae Sun'), ('PAY-15', 105, 'Achat Piano Solo'), ('PAY-16', 84, 'Achat Techno Rave'), ('PAY-17', 68, 'Achat Soul Train'), ('PAY-18', 120, 'Achat Circus Gala'), ('PAY-19', 58, 'Achat Punk Spirit'), ('PAY-20', 100, 'Achat Latin Dance');

INSERT INTO "public"."performe" ("id_perform", "id_even") 
    VALUES ('P-01', 'E-01'), ('P-02', 'E-02'), ('P-03', 'E-03'), ('P-04', 'E-04'), ('P-05', 'E-05'), ('P-06', 'E-06'), ('P-07', 'E-07'), ('P-08', 'E-08'), ('P-09', 'E-09'), ('P-10', 'E-10'), ('P-11', 'E-11'), ('P-12', 'E-12'), ('P-13', 'E-13'), ('P-14', 'E-14'), ('P-15', 'E-15'), ('P-16', 'E-16'), ('P-17', 'E-17'), ('P-18', 'E-18'), ('P-19', 'E-19'), ('P-20', 'E-20');

INSERT INTO "public"."performer" ("id_perform", "nom_scene", "nom", "prenom", "date_naiss", "nationalite", "biographie") 
    VALUES ('P-01', 'Rockstar Jo', 'Smith', 'John', '1985-05-12', 'USA', 'Bio rock'), ('P-02', 'Jazz Man', 'Davis', 'Miles', '1990-11-23', 'UK', 'Bio jazz'), ('P-03', 'The Funnyman', 'Garcia', 'Carlos', '1988-03-14', 'Espagne', 'Bio humour'), ('P-04', 'Pop Princess', 'Taylor', 'Emma', '1995-07-20', 'USA', 'Bio pop'), ('P-05', 'Master Magic', 'Houdi', 'Luc', '1982-12-01', 'France', 'Bio magie'), ('P-06', 'DJ Electro', 'Vidal', 'Marc', '1992-09-09', 'France', 'Bio electro'), ('P-07', 'Metal Lord', 'Irons', 'Steve', '1975-04-30', 'UK', 'Bio metal'), ('P-08', 'Soprano', 'Muller', 'Anna', '1980-01-15', 'Allemagne', 'Bio classique'), ('P-09', 'Folk Girl', 'Green', 'Lily', '1998-06-22', 'Canada', 'Bio folk'), ('P-10', 'MC Rap', 'Jones', 'Kevin', '1993-10-10', 'USA', 'Bio rap'), ('P-11', 'Dance Crew', 'Ballet', 'Group', '2000-01-01', 'France', 'Bio danse'), ('P-12', 'Blues King', 'King', 'BB', '1970-05-15', 'USA', 'Bio blues'), ('P-13', 'Clowny', 'Rigo', 'Jean', '1985-02-28', 'France', 'Bio enfant'), ('P-14', 'Bob Marley Fan', 'Sun', 'Sunny', '1990-08-21', 'Jamaique', 'Bio reggae'), ('P-15', 'Pianiste', 'Liszt', 'Franz', '1984-11-12', 'Hongrie', 'Bio piano'), ('P-16', 'Rave Master', 'Techno', 'Tonio', '1994-03-03', 'Belgique', 'Bio techno'), ('P-17', 'Soul Diva', 'Brown', 'Sarah', '1989-12-25', 'USA', 'Bio soul'), ('P-18', 'Acrobat', 'Zanni', 'Mario', '1991-05-05', 'Italie', 'Bio cirque'), ('P-19', 'Punk Kid', 'Vicious', 'Sid', '1996-02-14', 'UK', 'Bio punk'), ('P-20', 'Salsa King', 'Lopez', 'Pedro', '1987-07-07', 'Colombie', 'Bio latin');

INSERT INTO "public"."personnes_en_attente" ("code_file_attente", "date_inscrip", "rang", "id_seance", "id_client") 
    VALUES ('FA-01', '2026-05-13 10:00:00+00', 1, 'SEA-01', 'C-10'), ('FA-02', '2026-05-13 10:05:00+00', 2, 'SEA-01', 'C-11'), ('FA-03', '2026-05-13 10:10:00+00', 3, 'SEA-01', 'C-12');

INSERT INTO "public"."remboursement" ("code_rembours", "motif", "statut_rembours") 
    VALUES ('PAY-07', 'Annulation client', 'Demande'), ('PAY-19', 'Annulation client', 'Effectué'), ('PAY-20', 'Erreur tarif', 'En_cours');

INSERT INTO "public"."salle" ("id_salle", "nom", "capacite_max", "adresse", "plan_salle") 
    VALUES ('S-01', 'Le Zenith', 5000, '123 Rue de la Musique', '{"type":"Buffer","data":[112,108,97,110,49]}'), ('S-02', 'L''Olympia', 2000, '28 Bld des Capucines', '{"type":"Buffer","data":[112,108,97,110,50]}'), ('S-03', 'Accor Arena', 20000, '8 Bd de Bercy', '{"type":"Buffer","data":[112,108,97,110,51]}'), ('S-04', 'La Cigale', 1000, '120 Bd de Rochechouart', '{"type":"Buffer","data":[112,108,97,110,52]}'), ('S-05', 'Le Bataclan', 1500, '50 Bd Voltaire', '{"type":"Buffer","data":[112,108,97,110,53]}'), ('S-06', 'Casino de Paris', 1500, '16 Rue de Clichy', '{"type":"Buffer","data":[112,108,97,110,54]}'), ('S-07', 'Trianon', 1000, '80 Bd de Rochechouart', '{"type":"Buffer","data":[112,108,97,110,55]}'), ('S-08', 'Stade de France', 80000, 'ZAC du Cornillon', '{"type":"Buffer","data":[112,108,97,110,56]}'), ('S-09', 'U Arena', 30000, '8 Rue des Sorins', '{"type":"Buffer","data":[112,108,97,110,57]}'), ('S-10', 'Grand Rex', 2800, '1 Bd Poissonniere', '{"type":"Buffer","data":[112,108,97,110,49,48]}'), ('S-11', 'Salle Pleyel', 2000, '252 Rue du Fbg Saint-Honore', '{"type":"Buffer","data":[112,108,97,110,49,49]}'), ('S-12', 'La Gaite Lyrique', 700, '3 bis Rue Papin', '{"type":"Buffer","data":[112,108,97,110,49,50]}'), ('S-13', 'New Morning', 500, '7 Rue des Petites Ecuries', '{"type":"Buffer","data":[112,108,97,110,49,51]}'), ('S-14', 'La Bellevilloise', 400, '19 Rue Boyer', '{"type":"Buffer","data":[112,108,97,110,49,52]}'), ('S-15', 'La Machine', 800, '90 Bd de Clichy', '{"type":"Buffer","data":[112,108,97,110,49,53]}'), ('S-16', 'Zenith de Lille', 7000, '1 Bd des Cites Unies', '{"type":"Buffer","data":[112,108,97,110,49,54]}'), ('S-17', 'Halle Tony Garnier', 17000, '20 Place Docteurs Merieux', '{"type":"Buffer","data":[112,108,97,110,49,55]}'), ('S-18', 'Arkea Arena', 11000, '48-50 Avenue Jean Alfonséa', '{"type":"Buffer","data":[112,108,97,110,49,56]}'), ('S-19', 'Palais des Sports', 4000, '1 Place de la Porte de Versailles', '{"type":"Buffer","data":[112,108,97,110,49,57]}'), ('S-20', 'Theatre Mogador', 1600, '25 Rue de Mogador', '{"type":"Buffer","data":[112,108,97,110,50,48]}');

INSERT INTO "public"."seance" ("id_seance", "date_seance", "heure_deb", "heure_fin", "statut_seance", "capacite_seance", "id_tarif", "id_even", "id_salle") 
    VALUES ('SEA-01', '2026-07-01', '20:00:00', '23:00:00', 'Disponible', 5000, 'T-01', 'E-01', 'S-01'), ('SEA-02', '2026-08-10', '21:00:00', '23:30:00', 'Complète', 2000, 'T-02', 'E-02', 'S-02'), ('SEA-03', '2026-08-05', '19:30:00', '21:00:00', 'Disponible', 2800, 'T-03', 'E-03', 'S-03'), ('SEA-04', '2026-09-12', '20:30:00', '23:00:00', 'Annulée', 20000, 'T-04', 'E-04', 'S-04'), ('SEA-05', '2026-10-01', '18:00:00', '20:00:00', 'Disponible', 1000, 'T-05', 'E-05', 'S-05'), ('SEA-06', '2026-06-20', '14:00:00', '23:00:00', 'Passée', 1500, 'T-06', 'E-06', 'S-06'), ('SEA-07', '2026-11-15', '20:00:00', '22:30:00', 'Disponible', 80000, 'T-07', 'E-07', 'S-07'), ('SEA-08', '2026-12-20', '17:00:00', '19:30:00', 'Complète', 2000, 'T-08', 'E-08', 'S-08'), ('SEA-09', '2026-06-05', '21:00:00', '23:00:00', 'Passée', 500, 'T-09', 'E-09', 'S-09'), ('SEA-10', '2026-07-25', '22:00:00', '23:50:00', 'Disponible', 800, 'T-10', 'E-10', 'S-10'), ('SEA-11', '2026-08-20', '20:00:00', '22:00:00', 'Annulée', 1500, 'T-11', 'E-11', 'S-11'), ('SEA-12', '2026-09-01', '19:00:00', '21:30:00', 'Disponible', 1000, 'T-12', 'E-12', 'S-12'), ('SEA-13', '2026-10-15', '15:00:00', '17:00:00', 'Complète', 700, 'T-13', 'E-13', 'S-13'), ('SEA-14', '2026-07-05', '16:00:00', '21:00:00', 'Passée', 400, 'T-14', 'E-14', 'S-14'), ('SEA-15', '2026-11-05', '20:30:00', '22:30:00', 'Disponible', 30000, 'T-15', 'E-15', 'S-15'), ('SEA-16', '2026-12-31', '21:00:00', '23:55:00', 'Disponible', 7000, 'T-16', 'E-16', 'S-16'), ('SEA-17', '2026-10-25', '20:00:00', '22:30:00', 'Annulée', 17000, 'T-17', 'E-17', 'S-17'), ('SEA-18', '2026-12-10', '19:30:00', '22:30:00', 'Disponible', 11000, 'T-18', 'E-18', 'S-18'), ('SEA-19', '2026-08-28', '21:00:00', '23:30:00', 'Complète', 4000, 'T-19', 'E-19', 'S-19'), ('SEA-20', '2026-09-30', '20:00:00', '22:30:00', 'Disponible', 1600, 'T-20', 'E-20', 'S-20');

INSERT INTO "public"."tarif" ("id_tarif", "prix_fosse", "prix_vip", "prix_cat1", "prix_cat2", "prix_cat3") 
    VALUES ('T-01', 45, 150, 85, 65, 40), ('T-02', 30, 100, 60, 45, 25), ('T-03', 55, 200, 95, 75, 50), ('T-04', 40, 120, 70, 55, 35), ('T-05', 50, 180, 90, 70, 45), ('T-06', 35, 110, 65, 50, 30), ('T-07', 60, 250, 110, 85, 60), ('T-08', 25, 80, 50, 40, 20), ('T-09', 70, 300, 130, 100, 75), ('T-10', 48, 160, 88, 68, 42), ('T-11', 42, 140, 82, 62, 38), ('T-12', 38, 130, 78, 58, 32), ('T-13', 52, 190, 92, 72, 48), ('T-14', 33, 105, 62, 48, 28), ('T-15', 58, 220, 105, 80, 55), ('T-16', 44, 145, 84, 64, 41), ('T-17', 37, 115, 68, 52, 34), ('T-18', 65, 280, 120, 95, 68), ('T-19', 28, 95, 58, 43, 22), ('T-20', 54, 210, 100, 78, 52);

















