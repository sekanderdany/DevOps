import yaml

with open("debugging.yaml", "r") as stream:
    try:
        file = yaml.safe_load(stream)
        choices = file["config"]["choices"]
        code = file["config"]["options"][2]
        print(code)
    except yaml.YAMLError as e:
        print(e)
