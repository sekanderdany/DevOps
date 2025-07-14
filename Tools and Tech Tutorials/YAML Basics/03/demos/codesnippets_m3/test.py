import yaml

with open("summary_advanced_syntax.yaml", "r") as stream:
    try:
        print(yaml.safe_load(stream))
    except yaml.YAMLError as e:
        print(e)
